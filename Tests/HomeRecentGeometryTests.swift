import XCTest

final class HomeRecentGeometryTests: XCTestCase {
    func testNarrowWindowsStackHighlightAboveThumbnails() {
        for width: CGFloat in [320, 600, 800, 999] {
            let layout = HomeRecentGeometry.resolve(width: width, itemCount: 30)
            XCTAssertFalse(layout.sideBySide)
            XCTAssertEqual(layout.artwork, .thumbnail)
            XCTAssertEqual(layout.leadWidth, width)
            XCTAssertEqual(layout.rows, 1)
            assertFilledGrid(layout)
        }
    }

    func testWideLayoutsFillWidthAndAlignBottomEdges() {
        for width: CGFloat in [1000, 1100, 1280, 1440, 1920, 2560, 3440, 3795, 5120] {
            for count in [2, 3, 5, 9, 16, 32] {
                let layout = HomeRecentGeometry.resolve(width: width, itemCount: count)
                XCTAssertTrue(layout.sideBySide)
                XCTAssertEqual(layout.leadWidth + HomeRecentGeometry.sectionSpacing + layout.supportingWidth,
                               width, accuracy: 0.001)
                XCTAssertEqual(layout.leadHeight, layout.supportingHeight, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(layout.leadWidth, width * 0.42 - 0.001)
                XCTAssertGreaterThan(layout.artworkHeight, 0)
                XCTAssertLessThanOrEqual(layout.displayedCount, count)
                assertFilledGrid(layout)
            }
        }
    }

    func testResizeAdaptsArtworkAndNumberOfTitles() {
        let layouts = stride(from: 1000, through: 3800, by: 100).map {
            HomeRecentGeometry.resolve(width: CGFloat($0), itemCount: 32)
        }
        XCTAssertTrue(layouts.contains { $0.artwork == .poster })
        XCTAssertTrue(layouts.contains { $0.artwork == .thumbnail })
        XCTAssertGreaterThan(Set(layouts.map(\.supportingCount)).count, 1)
        XCTAssertGreaterThan(layouts.last!.supportingCount, layouts.first!.supportingCount)
        XCTAssertTrue(layouts.allSatisfy { $0.leadHeight <= 680 })
    }

    func testEmptyAndSingleTitleDoNotReserveSupportingSpace() {
        for count in [0, 1] {
            let layout = HomeRecentGeometry.resolve(width: 1800, itemCount: count)
            XCTAssertFalse(layout.sideBySide)
            XCTAssertEqual(layout.supportingCount, 0)
            XCTAssertEqual(layout.leadWidth, 1800)
            XCTAssertEqual(layout.supportingHeight, 0)
        }
    }

    func testResizeKeepsEveryTitleExactlyOnceAndNewestInHighlight() {
        let titles = Array(0..<32)
        for width in stride(from: 300, through: 4000, by: 37) {
            let layout = HomeRecentGeometry.resolve(width: CGFloat(width), itemCount: titles.count)
            let featured = Array(titles.prefix(layout.displayedCount))
            let overflow = Array(titles.dropFirst(layout.displayedCount))
            XCTAssertEqual(featured.first, 0)
            XCTAssertEqual(featured + overflow, titles)
            XCTAssertEqual(featured.count - 1, layout.rows * layout.columns)
        }
    }

    private func assertFilledGrid(_ layout: HomeRecentGeometry, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(CGFloat(layout.columns) * layout.cardWidth
                       + CGFloat(layout.columns - 1) * HomeRecentGeometry.cardSpacing,
                       layout.supportingWidth, accuracy: 0.001, file: file, line: line)
    }
}
