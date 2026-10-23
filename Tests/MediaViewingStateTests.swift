import XCTest
@testable import JellyfinKit

final class MediaViewingStateTests: XCTestCase {
    private func item(_ json: String) throws -> BaseItem {
        try JSONDecoder().decode(BaseItem.self, from: Data(json.utf8))
    }

    func testMovieResumeAndFallbackProgress() throws {
        let movie = try item(#"{"Id":"m","Name":"Movie","Type":"Movie","RunTimeTicks":60000000000,"UserData":{"PlaybackPositionTicks":28920000000}}"#)
        XCTAssertEqual(movie.resumeTimestamp, "48:12")
        XCTAssertEqual(movie.playbackActionTitle, "Resume · 48:12")
        XCTAssertEqual(try XCTUnwrap(movie.viewingProgress), 0.482, accuracy: 0.001)
        XCTAssertEqual(movie.viewingStatus, "In progress · 48:12")
    }

    func testWatchedMovieDoesNotAppearInProgress() throws {
        let movie = try item(#"{"Id":"m","Name":"Movie","Type":"Movie","UserData":{"Played":true,"PlayedPercentage":100,"PlaybackPositionTicks":28920000000}}"#)
        XCTAssertEqual(movie.playbackActionTitle, "Play")
        XCTAssertNil(movie.viewingProgress)
        XCTAssertEqual(movie.viewingStatus, "Watched")
    }

    func testSeriesProgressIsNotAResumePosition() throws {
        let series = try item(#"{"Id":"s","Name":"Series","Type":"Series","UserData":{"PlaybackPositionTicks":28920000000,"PlayedPercentage":50,"UnplayedItemCount":3}}"#)
        XCTAssertEqual(series.resumePositionSeconds, 0)
        XCTAssertEqual(series.viewingProgress, 0.5)
        XCTAssertEqual(series.viewingStatus, "3 unwatched episodes")
    }

    func testEpisodeActionIncludesEpisodeCode() throws {
        let episode = try item(#"{"Id":"e","Name":"Episode","Type":"Episode","ParentIndexNumber":2,"IndexNumber":4,"UserData":{"PlaybackPositionTicks":10000000}}"#)
        XCTAssertEqual(episode.playbackActionTitle, "Resume S2 E4")
    }

    func testMissingAndNegativeProgressAreSafe() throws {
        let movie = try item(#"{"Id":"m","Name":"Movie","Type":"Movie","UserData":{"PlaybackPositionTicks":-1,"PlayedPercentage":-10}}"#)
        XCTAssertEqual(movie.playbackActionTitle, "Play")
        XCTAssertNil(movie.viewingProgress)
    }

    func testProgressClampsAndTimestampIncludesHours() throws {
        let movie = try item(#"{"Id":"m","Name":"Movie","Type":"Movie","UserData":{"PlaybackPositionTicks":36610000000,"PlayedPercentage":150}}"#)
        XCTAssertEqual(movie.viewingProgress, 1)
        XCTAssertEqual(movie.resumeTimestamp, "1:01:01")
    }
}
