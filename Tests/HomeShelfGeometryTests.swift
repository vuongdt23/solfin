import XCTest

final class HomeShelfGeometryTests: XCTestCase {
    func testUltrawideShelfUsesAllAvailableWidth() {
        XCTAssertEqual(HomeShelfGeometry.contentWidth(viewport: 2560, leadingInset: 82), 2446)
        XCTAssertEqual(HomeShelfGeometry.contentWidth(viewport: 3440, leadingInset: 202), 3206)
    }

    func testNarrowShelfReservesSidebarAndTrailingInset() {
        XCTAssertEqual(HomeShelfGeometry.contentWidth(viewport: 900, leadingInset: 202), 666)
        XCTAssertEqual(HomeShelfGeometry.contentWidth(viewport: 100, leadingInset: 202), 1)
    }

    func testWheelMovesInBothDirectionsAndClampsToEdges() {
        XCTAssertEqual(HomeShelfGeometry.targetX(current: 100, delta: -60, documentWidth: 2000, viewportWidth: 900), 160)
        XCTAssertEqual(HomeShelfGeometry.targetX(current: 100, delta: 60, documentWidth: 2000, viewportWidth: 900), 40)
        XCTAssertEqual(HomeShelfGeometry.targetX(current: 100, delta: 600, documentWidth: 2000, viewportWidth: 900), 0)
        XCTAssertEqual(HomeShelfGeometry.targetX(current: 1000, delta: -600, documentWidth: 2000, viewportWidth: 900), 1100)
    }

    func testResizeClampsOffsetAndNonOverflowingShelfDoesNotScroll() {
        XCTAssertEqual(HomeShelfGeometry.targetX(current: 1100, delta: 0, documentWidth: 2000, viewportWidth: 1600), 400)
        XCTAssertEqual(HomeShelfGeometry.targetX(current: 0, delta: -60, documentWidth: 500, viewportWidth: 900), 0)
    }
}
