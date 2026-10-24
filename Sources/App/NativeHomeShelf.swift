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
    func updateNSView(_ view: HomeShelfWheelView, context: Context) {
        view.scheduleScrollerUpdate()
    }
}

final class HomeShelfWheelView: NSView {
    private var monitor: Any?
    private var scrollerUpdatePending = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        scheduleScrollerUpdate()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                  let root = window.contentView else { return event }
            guard let scrollView = self.shelf(in: root) else { return event }
            self.hideScrollers(in: scrollView)
            // Native horizontal gestures retain AppKit's momentum handling.
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
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

    override func layout() {
        super.layout()
        scheduleScrollerUpdate()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleScrollerUpdate()
    }

    func scheduleScrollerUpdate() {
        guard !scrollerUpdatePending else { return }
        scrollerUpdatePending = true
        // SwiftUI can reset NSScrollView properties during its update pass.
        // Apply after that pass, once the shelf's native frame is available.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollerUpdatePending = false
            guard let root = self.window?.contentView,
                  let scroll = self.shelf(in: root) else { return }
            self.hideScrollers(in: scroll)
        }
    }

    private func hideScrollers(in scroll: NSScrollView) {
        if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
        if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
        scroll.horizontalScroller?.isHidden = true
        scroll.verticalScroller?.isHidden = true
    }

    private func shelf(in root: NSView) -> NSScrollView? {
        let canvas = convert(bounds, to: nil)
        if let scroll = root as? NSScrollView {
            let clip = scroll.contentView
            let candidate = scroll.convert(scroll.bounds, to: nil)
            let clipCanvas = clip.convert(clip.bounds, to: nil)
            // Match the outer frame as well as the clip: macOS's Always setting
            // reserves a scrollbar gutter, so clip height alone does not match.
            let outerMatches = abs(candidate.minX - canvas.minX) < 4
                && abs(candidate.minY - canvas.minY) < 4
                && abs(candidate.width - canvas.width) < 4
                && abs(candidate.height - canvas.height) < 4
            let clipMatches = abs(clipCanvas.minX - canvas.minX) < 4
                && abs(clipCanvas.minY - canvas.minY) < 4
                && abs(clipCanvas.width - canvas.width) < 4
                && abs(clipCanvas.height - canvas.height) < 4
            if canvas.width > 0 && canvas.height > 0 && (outerMatches || clipMatches) {
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
