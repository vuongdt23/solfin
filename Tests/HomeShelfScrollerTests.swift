import XCTest
import AppKit

final class HomeShelfScrollerTests: XCTestCase {
    @MainActor
    func testLegacyScrollbarsHiddenWithoutDisablingScrolling() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        window.contentView = root
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 30, width: 800, height: 220))
        scroll.scrollerStyle = .legacy
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 2000, height: 200))
        scroll.documentView = document
        root.addSubview(scroll)
        let observer = HomeShelfWheelView(frame: scroll.frame)
        root.addSubview(observer)
        scroll.tile()
        XCTAssertTrue(scroll.hasHorizontalScroller)
        XCTAssertLessThan(scroll.contentView.bounds.height, observer.bounds.height)
        observer.scheduleScrollerUpdate()
        // Let the deferred post-SwiftUI enforcement run without requiring a display.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertFalse(scroll.hasVerticalScroller)
        scroll.contentView.scroll(to: NSPoint(x: 100, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(scroll.contentView.bounds.minX, 100, accuracy: 1)
        XCTAssertEqual(document.frame.width, 2000)
    }

    @MainActor
    func testWheelRoutingRequiresHoverAndPointInsideShelf() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        window.contentView = root
        let observer = HomeShelfWheelView(frame: NSRect(x: 20, y: 100, width: 800, height: 200))
        root.addSubview(observer)
        let inside = observer.convert(NSPoint(x: 100, y: 100), to: nil)
        let outside = observer.convert(NSPoint(x: 100, y: 250), to: nil)
        XCTAssertFalse(observer.shouldHandleWheel(at: inside))
        observer.isEnabled = true
        XCTAssertTrue(observer.shouldHandleWheel(at: inside))
        XCTAssertFalse(observer.shouldHandleWheel(at: outside))
        observer.isHidden = true
        XCTAssertFalse(observer.shouldHandleWheel(at: inside))
    }

    func testVerticalGesturesNeverBecomeHorizontalShelfInput() {
        XCTAssertTrue(HomeShelfWheelView.isVerticalGesture(deltaX: 0, deltaY: -30))
        XCTAssertTrue(HomeShelfWheelView.isVerticalGesture(deltaX: 2, deltaY: 30))
        XCTAssertFalse(HomeShelfWheelView.isVerticalGesture(deltaX: -30, deltaY: 2))
        XCTAssertFalse(HomeShelfWheelView.isVerticalGesture(deltaX: 30, deltaY: 0))
        XCTAssertFalse(HomeShelfWheelView.isVerticalGesture(deltaX: 0, deltaY: 0))
    }

    @MainActor
    func testVerticalInputTargetsEnclosingPageNotShelf() {
        let page = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 2000))
        page.documentView = document
        let shelf = NSScrollView(frame: NSRect(x: 0, y: 100, width: 800, height: 200))
        shelf.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 2000, height: 200))
        document.addSubview(shelf)
        let observer = HomeShelfWheelView()
        XCTAssertTrue(observer.verticalPage(above: shelf) === page)
        XCTAssertNil(observer.verticalPage(above: page))
    }

    @MainActor
    func testCoincidentPageFrameNeverDisablesVerticalScrolling() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        window.contentView = root
        let page = NSScrollView(frame: root.bounds)
        page.hasVerticalScroller = true
        page.hasHorizontalScroller = true
        page.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 2000))
        root.addSubview(page)
        let observer = HomeShelfWheelView(frame: page.frame)
        root.addSubview(observer)
        observer.scheduleScrollerUpdate()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(page.hasVerticalScroller)
        XCTAssertTrue(page.hasHorizontalScroller)
        page.contentView.scroll(to: NSPoint(x: 0, y: 100))
        XCTAssertEqual(page.contentView.bounds.minY, 100, accuracy: 1)
    }
}
