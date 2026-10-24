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
}
