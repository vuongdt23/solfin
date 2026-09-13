import XCTest
@testable import JellyfinKit

final class TicksTests: XCTestCase {
    func testSecondsToTicks() {
        XCTAssertEqual(Ticks.fromSeconds(1), 10_000_000)
        XCTAssertEqual(Ticks.fromSeconds(0), 0)
        XCTAssertEqual(Ticks.fromSeconds(2165.2), 21_652_000_000)
    }

    func testTicksToSeconds() {
        XCTAssertEqual(Ticks.toSeconds(10_000_000), 1, accuracy: 0.0001)
        XCTAssertEqual(Ticks.toSeconds(nil), 0)
        XCTAssertEqual(Ticks.toSeconds(21_652_000_000), 2165.2, accuracy: 0.0001)
    }

    func testRoundTrip() {
        for s in [0.0, 1.5, 59.9, 3600.0, 7325.25] {
            let round = Ticks.toSeconds(Ticks.fromSeconds(s))
            XCTAssertEqual(round, s, accuracy: 0.0001)
        }
    }
}
