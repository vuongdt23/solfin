import XCTest

final class HomeLayoutTests: XCTestCase {
    func testExistingAndUnknownPreferencesKeepOriginalHome() {
        XCTAssertEqual(HomeLayout.saved(""), .cinematic)
        XCTAssertEqual(HomeLayout.saved("future-mode"), .cinematic)
        XCTAssertEqual(HomeHeroStyle.saved(""), .full)
        XCTAssertEqual(HomeHeroStyle.saved("future-style"), .full)
    }

    func testPersistedIdentifiersRoundTrip() {
        XCTAssertEqual(HomeLayout.allCases.map(\.rawValue), ["cinematic", "watchNow", "library"])
        XCTAssertEqual(HomeHeroStyle.allCases.map(\.rawValue), ["full", "spotlight"])
        for mode in HomeLayout.allCases { XCTAssertEqual(HomeLayout.saved(mode.rawValue), mode) }
        for style in HomeHeroStyle.allCases { XCTAssertEqual(HomeHeroStyle.saved(style.rawValue), style) }
    }

    func testCinematicAddsEditorialDiscoveryAfterResumeBridge() {
        XCTAssertEqual(HomeLayout.cinematic.sections, [.watching, .discover, .recentlyAdded, .libraries])
    }

    func testWatchNowPrioritizesPlaybackThenDiscovery() {
        XCTAssertEqual(HomeLayout.watchNow.sections, [.watching, .discover, .recentlyAdded, .libraries])
    }

    func testLibraryPrioritizesBrowsingWithoutDiscoveryHero() {
        XCTAssertEqual(HomeLayout.library.sections, [.libraries, .recentlyAdded, .watching])
        XCTAssertFalse(HomeLayout.library.sections.contains(.discover))
    }

    func testLibraryArtworkDefaultsToFanAndKeepsOnlyFanAndRandom() {
        XCTAssertEqual(HomeLibraryArtworkStyle.saved(""), .fan)
        XCTAssertEqual(HomeLibraryArtworkStyle.saved("wall"), .fan)
        XCTAssertEqual(HomeLibraryArtworkStyle.allCases.map(\.rawValue), ["fan", "random"])
        XCTAssertEqual(HomeLibraryArtworkStyle.saved("random"), .random)
    }

    func testModesHaveUniqueSectionsAndDisplayCopy() {
        for mode in HomeLayout.allCases {
            XCTAssertEqual(Set(mode.sections).count, mode.sections.count)
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.summary.isEmpty)
            XCTAssertFalse(mode.symbol.isEmpty)
        }
    }
}
