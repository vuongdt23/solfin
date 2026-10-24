import XCTest
import JellyfinKit

final class HomePresentationTests: XCTestCase {
    private func item(_ id: String, type: String = "Movie", extra: String = "") throws -> BaseItem {
        let json = "{\"Id\":\"\(id)\",\"Name\":\"Title \(id)\",\"Type\":\"\(type)\"\(extra)}"
        return try JSONDecoder().decode(BaseItem.self, from: Data(json.utf8))
    }

    func testResumeLeadPreservesServerOrderAndDeduplicatesSupporting() throws {
        let a = try item("a"), b = try item("b"), c = try item("c", type: "Episode")
        let selection = HomePresentation.watchSelection(resume: [a, b], nextUp: [a, c, c], discovery: [])
        XCTAssertEqual(selection.lead?.id, "a")
        XCTAssertEqual(selection.supporting.map(\.id), ["c", "b"])
    }

    func testNextUpAndDiscoveryFallbacks() throws {
        let episode = try item("episode", type: "Episode"), movie = try item("movie")
        XCTAssertEqual(HomePresentation.watchSelection(resume: [], nextUp: [episode], discovery: [movie]).lead?.id, "episode")
        XCTAssertEqual(HomePresentation.watchSelection(resume: [], nextUp: [], discovery: [movie]).lead?.id, "movie")
        XCTAssertNil(HomePresentation.watchSelection(resume: [], nextUp: [], discovery: []).lead)
    }

    func testOfflineItemsNeverBecomeLeadOrSupporting() throws {
        let offline = try item("offline", extra: ",\"LocationType\":\"Offline\"")
        let available = try item("available")
        let selection = HomePresentation.watchSelection(resume: [offline], nextUp: [available, offline], discovery: [])
        XCTAssertEqual(selection.lead?.id, "available")
        XCTAssertTrue(selection.supporting.isEmpty)
    }

    func testSecondaryContentExcludesFeaturedIDsWithoutChangingOrder() throws {
        let a = try item("a"), b = try item("b"), c = try item("c")
        XCTAssertEqual(HomePresentation.unique([a, b, b, c], excluding: ["a"]).map(\.id), ["b", "c"])
    }

    func testRecentFilterAndDateOrdering() throws {
        let movie = try item("movie", extra: ",\"DateCreated\":\"2026-10-01T00:00:00Z\"")
        let show = try item("show", type: "Series", extra: ",\"DateCreated\":\"2026-10-02T00:00:00Z\"")
        XCTAssertEqual(HomePresentation.recent(movies: [movie], shows: [show], filter: .all).map(\.id), ["show", "movie"])
        XCTAssertEqual(HomePresentation.recent(movies: [movie], shows: [show], filter: .movies).map(\.id), ["movie"])
        XCTAssertEqual(HomePresentation.recent(movies: [movie], shows: [show], filter: .shows).map(\.id), ["show"])
    }

    func testMissingDatesPreserveStableInputOrder() throws {
        let a = try item("a"), b = try item("b")
        XCTAssertEqual(HomePresentation.recent(movies: [a, b], shows: [], filter: .all).map(\.id), ["a", "b"])
    }

    func testProgressAndRemainingTimePreferActualPosition() throws {
        let media = try item("a", extra: ",\"RunTimeTicks\":6000000000,\"UserData\":{\"PlaybackPositionTicks\":3000000000,\"PlayedPercentage\":10}")
        XCTAssertEqual(HomePresentation.progress(media), 0.5)
        XCTAssertEqual(HomePresentation.remaining(media), "5 min left")
    }

    func testMissingAndOutOfRangeProgress() throws {
        XCTAssertNil(HomePresentation.progress(try item("empty")))
        XCTAssertNil(HomePresentation.remaining(try item("empty")))
        let finished = try item("done", extra: ",\"RunTimeTicks\":6000000000,\"UserData\":{\"PlayedPercentage\":120}")
        XCTAssertEqual(HomePresentation.progress(finished), 1)
        XCTAssertNil(HomePresentation.remaining(finished))
    }

    func testEpisodeIdentityWithMissingNumbers() throws {
        let episode = try item("episode", type: "Episode", extra: ",\"ParentIndexNumber\":2,\"IndexNumber\":3")
        XCTAssertEqual(HomePresentation.episodeIdentity(episode), "S2E3 · Title episode")
        XCTAssertEqual(HomePresentation.episodeIdentity(try item("episode", type: "Episode")), "Title episode")
        XCTAssertNil(HomePresentation.episodeIdentity(try item("movie")))
    }
}
