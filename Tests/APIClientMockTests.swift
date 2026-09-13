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
            guard request.url?.path == "/Users/u1/Items" else {
                XCTFail("Unexpected path: \(request.url?.path ?? "nil")")
                return (404, Data())
            }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let includeTypes = query.first { $0.name == "IncludeItemTypes" }?.value

            if includeTypes == "Episode" {
                XCTAssertEqual(query.first { $0.name == "ParentId" }?.value, "tv")
                XCTAssertEqual(query.first { $0.name == "SortBy" }?.value, "DateCreated")
                XCTAssertEqual(query.first { $0.name == "SortOrder" }?.value, "Descending")
                XCTAssertEqual(query.first { $0.name == "Recursive" }?.value, "true")
                let json = """
                {"Items":[
                  {"Id":"ep4","Name":"Newest B","Type":"Episode","SeriesId":"seriesB","DateCreated":"2026-09-12T00:00:00.0000000Z"},
                  {"Id":"ep3","Name":"Newest A","Type":"Episode","SeriesId":"seriesA","DateCreated":"2026-09-11T00:00:00.0000000Z"},
                  {"Id":"ep2","Name":"Older B","Type":"Episode","SeriesId":"seriesB","DateCreated":"2026-09-10T00:00:00.0000000Z"}
                ],"TotalRecordCount":3}
                """
                return (200, Data(json.utf8))
            }

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
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.path, "/Users/u1/Items")
        XCTAssertEqual(MockURLProtocol.requests.last?.url?.path, "/Users/u1/Items")
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

    func testUnauthenticatedBrowseThrows() async {
        let client = makeClient(authed: false)
        do { _ = try await client.views(); XCTFail("expected notAuthenticated") }
        catch { XCTAssertTrue(error is JellyfinError) }
    }
}
