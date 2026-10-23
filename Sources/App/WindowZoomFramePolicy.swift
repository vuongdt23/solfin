import AppKit
import SwiftUI

/// Makes the green-button zoom use the screen's usable area, excluding the menu
/// bar and Dock, rather than a content-derived frame that can extend underneath them.
struct WindowZoomFramePolicy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowZoomFrameView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowZoomFrameView: NSView {
    private var zoomDelegate: StandardWindowZoomDelegate?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        if let zoomDelegate, window.delegate === zoomDelegate { return }
        let delegate = StandardWindowZoomDelegate(forwarding: window.delegate)
        zoomDelegate = delegate
        window.delegate = delegate
    }
}

/// Intercepts only standard-frame selection and forwards all other optional
/// NSWindowDelegate messages to SwiftUI's existing delegate.
private final class StandardWindowZoomDelegate: NSObject, NSWindowDelegate {
    private weak var forwardedDelegate: (any NSWindowDelegate)?

    init(forwarding delegate: (any NSWindowDelegate)?) {
        forwardedDelegate = delegate
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        window.screen?.visibleFrame ?? newFrame
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwardedDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        guard forwardedDelegate?.responds(to: selector) == true else {
            return super.forwardingTarget(for: selector)
        }
        return forwardedDelegate
    }
}
