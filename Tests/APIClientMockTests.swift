import XCTest
@testable import JellyfinKit

final class APIClientMockTests: XCTestCase {
    private let base = URL(string: "http://localhost:8096")!

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient(authed: Bool) -> APIClient {
        let info = ClientInfo(deviceId: "DEV1")
        let session = authed ? ServerSession(serverURL: base, userId: "u1",
                                             userName: "admin", accessToken: "TOK") : nil
        return APIClient(baseURL: base, clientInfo: info, session: session,
                         urlSession: MockURLProtocol.makeSession())
    }

    func testLoginParsesTokenAndUser() async throws {
        MockURLProtocol.handler = { _ in
            let json = #"{"User":{"Id":"user-42","Name":"admin"},"AccessToken":"secret","ServerId":"srv"}"#
            return (200, Data(json.utf8))
        }
        let session = try await makeClient(authed: false)
            .login(username: "admin", password: "pw")
        XCTAssertEqual(session.userId, "user-42")
        XCTAssertEqual(session.userName, "admin")
        XCTAssertEqual(session.accessToken, "secret")
        XCTAssertEqual(session.serverURL, base)
    }

    func testItemsDropsOfflineEntriesAndFoldersFromLibraryResults() async throws {
        MockURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(query.first(where: { $0.name == "Fields" })?.value?.contains("LocationType") == true)
            let json = #"{"Items":[{"Id":"available","Name":"Available","Type":"Movie","LocationType":"FileSystem"},{"Id":"missing","Name":"Missing","Type":"Movie","LocationType":"Offline"},{"Id":"folder","Name":"Empty folder","Type":"Folder","LocationType":"FileSystem"}],"TotalRecordCount":3}"#
            return (200, Data(json.utf8))
        }

        let response = try await makeClient(authed: true).items(parentId: "movies", limit: 60,
                                                                 includeItemTypes: "Movie")
        XCTAssertEqual(response.items.map(\.id), ["available", "missing", "folder"])
        XCTAssertEqual(response.totalRecordCount, 3)
        XCTAssertEqual(response.items.filter(\.isBrowsableMedia).map(\.id), ["available"])
    }

    func testLibrarySearchKeepsScopeFiltersSortAndPagination() async throws {
        MockURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
            XCTAssertEqual(value("ParentId"), "movies")
            XCTAssertEqual(value("SearchTerm"), "The Bear & Friends")
            XCTAssertEqual(value("Filters"), "IsUnplayed")
            XCTAssertEqual(value("SortBy"), "ProductionYear")
            XCTAssertEqual(value("SortOrder"), "Descending")
            XCTAssertEqual(value("StartIndex"), "60")
            XCTAssertEqual(value("Limit"), "60")
            XCTAssertEqual(value("Recursive"), "true")
            XCTAssertEqual(value("EnableUserData"), "true")
            return (200, Data(#"{"Items":[],"TotalRecordCount":0}"#.utf8))
        }
        _ = try await makeClient(authed: true).items(
            parentId: "movies", startIndex: 60, limit: 60, sortBy: "ProductionYear", sortOrder: "Descending",
            includeItemTypes: "Movie", filters: "IsUnplayed", searchTerm: "The Bear & Friends")
    }

    func testRecentEpisodeSearchFiltersSeriesWithoutFilteringEpisodeActivity() async throws {
        MockURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if request.url?.path == "/Users/u1/Items/Latest" {
                XCTAssertNil(query.first { $0.name == "SearchTerm" })
                return (200, Data(#"[{"Id":"ep","Name":"Pilot","SeriesId":"s","DateCreated":"2026-10-01"}]"#.utf8))
            }
            XCTAssertEqual(query.first { $0.name == "SearchTerm" }?.value, "Bear")
            XCTAssertEqual(query.first { $0.name == "Filters" }?.value, "IsUnplayed")
            return (200, Data(#"{"Items":[{"Id":"s","Name":"The Bear","Type":"Series"}]}"#.utf8))
        }
        let result = try await makeClient(authed: true).recentlyActiveSeries(
            parentId: "tv", filters: "IsUnplayed", searchTerm: "Bear")
        XCTAssertEqual(result.map(\.id), ["s"])
    }

    func testDirectPlayPlanPicksDirectPlaySource() async throws {
        // Two sources: first is NOT direct-play, second IS — selection must pick the second.
        MockURLProtocol.handler = { _ in
            let json = """
            {"PlaySessionId":"ps1","MediaSources":[
              {"Id":"transcode","Container":"mkv","SupportsDirectPlay":false,"SupportsDirectStream":false},
              {"Id":"direct","Container":"mkv","SupportsDirectPlay":true,"SupportsDirectStream":true}
            ]}
            """
            return (200, Data(json.utf8))
        }
        let item = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"movie1","Name":"Avatar","UserData":{"PlaybackPositionTicks":21652000000}}"#.utf8))
        let plan = try await makeClient(authed: true).directPlayPlan(for: item)

        XCTAssertEqual(plan.mediaSourceId, "direct")
        XCTAssertEqual(plan.playSessionId, "ps1")
        XCTAssertEqual(plan.resumeSeconds, 2165.2, accuracy: 0.001)
        XCTAssertTrue(plan.streamURL.absoluteString.contains("/Videos/movie1/stream.mkv"))
        XCTAssertTrue(plan.streamURL.absoluteString.contains("mediaSourceId=direct"))
    }

    func testDirectPlayPlanBuildsExternalSubtitleFromPlaybackInfo() async throws {
        MockURLProtocol.handler = { _ in
            let payload = MockURLProtocol.lastBody.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            let profile = payload?["DeviceProfile"] as? [String: Any]
            let subtitleProfiles = profile?["SubtitleProfiles"] as? [[String: Any]] ?? []
            XCTAssertFalse(subtitleProfiles.isEmpty)
            XCTAssertTrue(subtitleProfiles.contains { ($0["Format"] as? String) == "srt" && ($0["Method"] as? String) == "External" })
            XCTAssertFalse(subtitleProfiles.contains { ($0["Format"] as? String) == "dvdsub" && ($0["Method"] as? String) == "External" })
            XCTAssertFalse(subtitleProfiles.contains { ($0["Format"] as? String) == "vobsub" && ($0["Method"] as? String) == "External" })

            let json = """
            {"PlaySessionId":"ps1","MediaSources":[{
              "Id":"source","Container":"mkv","SupportsDirectPlay":true,
              "DefaultAudioStreamIndex":2,"DefaultSubtitleStreamIndex":0,
              "MediaStreams":[
                {"Type":"Subtitle","Index":0,"Codec":"subrip","Language":"eng",
                 "DisplayTitle":"English","IsDefault":true,"IsExternal":true,
                 "DeliveryMethod":"External",
                 "DeliveryUrl":"/Videos/movie1/source/Subtitles/0/0/Stream.srt"},
                {"Type":"Video","Index":1,"Codec":"h264"},
                {"Type":"Audio","Index":2,"Codec":"aac"}
              ]
            }]}
            """
            return (200, Data(json.utf8))
        }
        let item = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"movie1","Name":"Movie"}"#.utf8))
        let plan = try await makeClient(authed: true).directPlayPlan(for: item)

        XCTAssertEqual(plan.defaultAudioStreamIndex, 2)
        XCTAssertEqual(plan.defaultSubtitleStreamIndex, 0)
        XCTAssertEqual(plan.externalSubtitles.count, 1)
        XCTAssertEqual(plan.externalSubtitles[0].streamIndex, 0)
        XCTAssertEqual(plan.externalSubtitles[0].language, "eng")
        XCTAssertTrue(plan.externalSubtitles[0].url.absoluteString.contains("api_key=TOK"))
    }

    func testDirectPlayPlanSkipsExternalBitmapSubtitleURLs() async throws {
        MockURLProtocol.handler = { _ in
            let json = """
            {"PlaySessionId":"ps1","MediaSources":[{
              "Id":"source","Container":"mkv","SupportsDirectPlay":true,
              "MediaStreams":[
                {"Type":"Subtitle","Index":0,"Codec":"dvdsub","Language":"eng",
                 "DisplayTitle":"English DVD","IsExternal":true,
                 "DeliveryMethod":"External",
                 "DeliveryUrl":"/Videos/movie1/source/Subtitles/0/Stream.sub"},
                {"Type":"Subtitle","Index":1,"Codec":"subrip","Language":"eng",
                 "DisplayTitle":"English SRT","IsExternal":true,
                 "DeliveryMethod":"External",
                 "DeliveryUrl":"/Videos/movie1/source/Subtitles/1/Stream.srt"}
              ]
            }]}
            """
            return (200, Data(json.utf8))
        }
        let item = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"movie1","Name":"Movie"}"#.utf8))
        let plan = try await makeClient(authed: true).directPlayPlan(for: item)

        XCTAssertEqual(plan.externalSubtitles.map(\.streamIndex), [1])
    }

    func testProgressReportSendsPositionTicks() async throws {
        MockURLProtocol.handler = { _ in (204, Data()) }
        let client = makeClient(authed: true)
        let plan = DirectPlayPlan(itemId: "m1", mediaSourceId: "s1", playSessionId: "ps1",
                                  streamURL: base, resumeSeconds: 0)
        try await client.reportPlaybackProgress(plan, positionSeconds: 100, isPaused: true)

        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["PositionTicks"] as? Int64, 1_000_000_000)
        XCTAssertEqual(json["IsPaused"] as? Bool, true)
        XCTAssertEqual(json["ItemId"] as? String, "m1")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/Sessions/Playing/Progress")
    }

    private func episodesJSON() -> String {
        """
        {"Items":[
          {"Id":"ep1","Name":"E1","Type":"Episode","SeriesId":"series1","IndexNumber":1},
          {"Id":"ep2","Name":"E2","Type":"Episode","SeriesId":"series1","IndexNumber":2},
          {"Id":"ep3","Name":"E3","Type":"Episode","SeriesId":"series1","IndexNumber":3}
        ],"TotalRecordCount":3}
        """
    }

    func testRecentlyActiveSeriesReturnsSeriesInLatestEpisodeOrder() async throws {
        MockURLProtocol.handler = { request in
            let path = request.url?.path
            guard path == "/Users/u1/Items" || path == "/Users/u1/Items/Latest" else {
                XCTFail("Unexpected path: \(path ?? "nil")")
                return (404, Data())
            }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let includeTypes = query.first { $0.name == "IncludeItemTypes" }?.value

            if includeTypes == "Episode" {
                XCTAssertEqual(path, "/Users/u1/Items/Latest")
                XCTAssertEqual(query.first { $0.name == "ParentId" }?.value, "tv")
                XCTAssertEqual(query.first { $0.name == "Limit" }?.value, "1000")
                let json = """
                [
                  {"Id":"ep4","Name":"Newest B","Type":"Episode","SeriesId":"seriesB","DateCreated":"2026-09-12T00:00:00.0000000Z"},
                  {"Id":"ep3","Name":"Newest A","Type":"Episode","SeriesId":"seriesA","DateCreated":"2026-09-11T00:00:00.0000000Z"},
                  {"Id":"ep2","Name":"Older B","Type":"Episode","SeriesId":"seriesB","DateCreated":"2026-09-10T00:00:00.0000000Z"}
                ]
                """
                return (200, Data(json.utf8))
            }

            XCTAssertEqual(path, "/Users/u1/Items")
            XCTAssertEqual(includeTypes, "Series")
            XCTAssertEqual(query.first { $0.name == "ParentId" }?.value, "tv")
            XCTAssertEqual(query.first { $0.name == "SortBy" }?.value, "SortName")
            XCTAssertEqual(query.first { $0.name == "SortOrder" }?.value, "Ascending")
            let json = """
            {"Items":[
              {"Id":"seriesC","Name":"Series C","Type":"Series"},
              {"Id":"seriesA","Name":"Series A","Type":"Series"},
              {"Id":"seriesB","Name":"Series B","Type":"Series"},
              {"Id":"seriesD","Name":"Series D","Type":"Series"}
            ],"TotalRecordCount":4}
            """
            return (200, Data(json.utf8))
        }

        let series = try await makeClient(authed: true).recentlyActiveSeries(parentId: "tv", limit: 20)

        XCTAssertEqual(series.map(\.id), ["seriesB", "seriesA", "seriesC", "seriesD"])
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertEqual(Set(MockURLProtocol.requests.compactMap { $0.url?.path }),
                       Set(["/Users/u1/Items", "/Users/u1/Items/Latest"]))
    }

    func testNextEpisodeReturnsFollowing() async throws {
        MockURLProtocol.handler = { _ in (200, Data(self.episodesJSON().utf8)) }
        let current = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"ep2","Name":"E2","Type":"Episode","SeriesId":"series1"}"#.utf8))
        let next = try await makeClient(authed: true).nextEpisode(after: current)
        XCTAssertEqual(next?.id, "ep3")
    }

    func testNextEpisodeNilOnLast() async throws {
        MockURLProtocol.handler = { _ in (200, Data(self.episodesJSON().utf8)) }
        let last = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"ep3","Name":"E3","Type":"Episode","SeriesId":"series1"}"#.utf8))
        let next = try await makeClient(authed: true).nextEpisode(after: last)
        XCTAssertNil(next)
    }

    func testNextEpisodeNilWithoutSeriesId() async throws {
        let movie = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"m1","Name":"Movie","Type":"Movie"}"#.utf8))
        let next = try await makeClient(authed: true).nextEpisode(after: movie)
        XCTAssertNil(next)   // no network call needed; returns nil immediately
    }

    func testLibraryPosterPreviewIsScopedAndSkipsMissingDuplicateAndOfflineArtwork() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/Users/u1/Items")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(query.first { $0.name == "ParentId" }?.value, "tv")
            XCTAssertEqual(query.first { $0.name == "IncludeItemTypes" }?.value, "Series")
            XCTAssertEqual(query.first { $0.name == "Limit" }?.value, "36")
            XCTAssertEqual(query.first { $0.name == "Recursive" }?.value, "true")
            XCTAssertEqual(query.first { $0.name == "SortBy" }?.value, "Random")
            XCTAssertEqual(query.first { $0.name == "HasPrimaryImage" }?.value, "true")
            XCTAssertEqual(query.first { $0.name == "EnableImages" }?.value, "true")
            let json = """
            {"Items":[
              {"Id":"missing","Name":"No art","Type":"Series"},
              {"Id":"a","Name":"A","Type":"Series","ImageTags":{"Primary":"pa"}},
              {"Id":"a","Name":"A duplicate","Type":"Series","ImageTags":{"Primary":"pa"}},
              {"Id":"offline","Name":"Offline","Type":"Series","LocationType":"Offline","ImageTags":{"Primary":"po"}},
              {"Id":"empty","Name":"Empty tag","Type":"Series","ImageTags":{"Primary":""}},
              {"Id":"b","Name":"B","Type":"Series","ImageTags":{"Primary":"pb"}},
              {"Id":"c","Name":"C","Type":"Series","ImageTags":{"Primary":"pc"}},
              {"Id":"d","Name":"D","Type":"Series","ImageTags":{"Primary":"pd"}}
            ]}
            """
            return (200, Data(json.utf8))
        }
        let library = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"tv","Name":"Shows","CollectionType":"tvshows"}"#.utf8))
        let posters = try await makeClient(authed: true).libraryPosterItems(for: library)
        XCTAssertEqual(posters.map(\.id), ["a", "b", "c", "d"])
    }

    func testLibraryPosterPreviewSelectsTypesAndHandlesEmptyLibrary() async throws {
        for (collection, expected) in [("movies", "Movie"), ("music", "MusicAlbum"),
                                       ("books", "Book"), ("mixed", "Movie,Series")] {
            MockURLProtocol.handler = { request in
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertEqual(query.first { $0.name == "IncludeItemTypes" }?.value, expected)
                XCTAssertEqual(query.first { $0.name == "ParentId" }?.value, "library")
                return (200, Data(#"{"Items":[]}"#.utf8))
            }
            let library = try JSONDecoder().decode(BaseItem.self, from: Data(
                "{\"Id\":\"library\",\"Name\":\"Library\",\"CollectionType\":\"\(collection)\"}".utf8))
            let posters = try await makeClient(authed: true).libraryPosterItems(for: library)
            XCTAssertTrue(posters.isEmpty)
        }
    }

    func testLibraryPosterPreviewPrefersDifferentTitlesOnReload() async throws {
        MockURLProtocol.handler = { _ in
            let items = (1...32).map { index in
                "{\"Id\":\"\(index)\",\"Name\":\"Title \(index)\",\"ImageTags\":{\"Primary\":\"p\(index)\"}}"
            }.joined(separator: ",")
            return (200, Data("{\"Items\":[\(items)]}".utf8))
        }
        let library = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"movies","Name":"Movies","CollectionType":"movies"}"#.utf8))
        let client = makeClient(authed: true)
        let first = try await client.libraryPosterItems(for: library)
        let second = try await client.libraryPosterItems(for: library, excluding: first.map(\.id))
        XCTAssertEqual(first.map(\.id), (1...24).map(String.init))
        XCTAssertEqual(second.map(\.id), (25...32).map(String.init) + (1...16).map(String.init))
    }

    func testLibraryPosterPreviewStillFillsSmallLibraryWithPreviousTitles() async throws {
        MockURLProtocol.handler = { _ in
            let json = #"{"Items":[{"Id":"a","Name":"A","ImageTags":{"Primary":"pa"}},{"Id":"b","Name":"B","ImageTags":{"Primary":"pb"}}]}"#
            return (200, Data(json.utf8))
        }
        let library = try JSONDecoder().decode(BaseItem.self, from: Data(
            #"{"Id":"tv","Name":"Shows","CollectionType":"tvshows"}"#.utf8))
        let posters = try await makeClient(authed: true).libraryPosterItems(for: library, excluding: ["a"])
        XCTAssertEqual(posters.map(\.id), ["b", "a"])
    }

    func testUnauthenticatedBrowseThrows() async {
        let client = makeClient(authed: false)
        do { _ = try await client.views(); XCTFail("expected notAuthenticated") }
        catch { XCTAssertTrue(error is JellyfinError) }
    }
}
