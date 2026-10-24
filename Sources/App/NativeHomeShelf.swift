import SwiftUI
import AppKit

private struct HomeShelfWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var homeShelfWidth: CGFloat? {
        get { self[HomeShelfWidthKey.self] }
        set { self[HomeShelfWidthKey.self] = newValue }
    }
}

/// Locates the shelf by its visible canvas, not by SwiftUI's private hit-test
/// hierarchy. The content stays in the original SwiftUI navigation environment.
struct HomeShelfWheelObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> HomeShelfWheelView { HomeShelfWheelView() }
    func updateNSView(_ view: HomeShelfWheelView, context: Context) { }
}

final class HomeShelfWheelView: NSView {
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                  let root = window.contentView else { return event }
            // Native horizontal gestures retain AppKit's momentum handling.
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let scrollView = self.shelf(in: root) else { return event }
            let clip = scrollView.contentView
            let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
            let x = HomeShelfGeometry.targetX(current: clip.bounds.minX, delta: delta,
                                             documentWidth: scrollView.documentView?.frame.width ?? 0,
                                             viewportWidth: clip.bounds.width)
            guard abs(x - clip.bounds.minX) > 0.1 else { return event }
            clip.scroll(to: CGPoint(x: x, y: clip.bounds.minY))
            scrollView.reflectScrolledClipView(clip)
            return nil
        }
    }

    private func shelf(in root: NSView) -> NSScrollView? {
        let canvas = convert(bounds, to: nil)
        if let scroll = root as? NSScrollView {
            let clip = scroll.contentView
            let candidate = clip.convert(clip.bounds, to: nil)
            // Match this shelf's canvas, never an overflowing vertical page.
            if abs(candidate.minX - canvas.minX) < 4,
               abs(candidate.minY - canvas.minY) < 4,
               abs(candidate.width - canvas.width) < 4,
               abs(candidate.height - canvas.height) < 4 {
                return scroll
            }
        }
        for child in root.subviews {
            if let found = shelf(in: child) { return found }
        }
        return nil
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
