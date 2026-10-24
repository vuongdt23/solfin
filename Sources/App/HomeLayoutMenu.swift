import SwiftUI
import AppKit

/// Native menu tracking must not be invalidated by SwiftUI hover updates.
/// Keep one button alive; construct menu contents only when it is opened.
struct HomeLayoutMenu: NSViewRepresentable {
    @Binding var layoutRaw: String
    @Binding var heroStyleRaw: String
    let isTopHovered: Bool

    func makeNSView(context: Context) -> HomeLayoutMenuButton {
        let button = HomeLayoutMenuButton()
        configure(button)
        return button
    }

    func updateNSView(_ button: HomeLayoutMenuButton, context: Context) {
        configure(button)
    }

    private func configure(_ button: HomeLayoutMenuButton) {
        button.layout = HomeLayout.saved(layoutRaw)
        button.heroStyle = HomeHeroStyle.saved(heroStyleRaw)
        button.selectLayout = { layoutRaw = $0.rawValue }
        button.selectHero = { heroStyleRaw = $0.rawValue }
        button.updateVisibility(isTopHovered)
    }
}

final class HomeLayoutMenuButton: NSButton {
    var layout = HomeLayout.cinematic
    var heroStyle = HomeHeroStyle.full
    var selectLayout: ((HomeLayout) -> Void)?
    var selectHero: ((HomeHeroStyle) -> Void)?
    private var menuOpen = false
    private var topHovered = false
    private var pendingHide: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        title = "Home Layout ▾"
        image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        imagePosition = .imageLeading
        bezelStyle = .rounded
        isBordered = true
        font = .systemFont(ofSize: 13, weight: .semibold)
        contentTintColor = .white
        target = self
        action = #selector(openLayoutMenu)
        setAccessibilityLabel("Home Layout")
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 154, height: 36) }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { pendingHide?.cancel(); alphaValue = 1 }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { updateVisibility(topHovered) }
        return accepted
    }

    private var pointerInside: Bool {
        guard let window, window.isKeyWindow else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    func updateVisibility(_ hovered: Bool) {
        topHovered = hovered
        pendingHide?.cancel()
        if hovered || pointerInside || menuOpen || window?.firstResponder === self {
            alphaValue = 1
        } else {
            // Ignore transient exits while crossing from page content to the
            // native button/menu. No opacity animation or tracking-area churn.
            let hide = DispatchWorkItem { [weak self] in
                guard let self, !self.topHovered, !self.pointerInside, !self.menuOpen,
                      self.window?.firstResponder !== self else { return }
                self.alphaValue = 0
            }
            pendingHide = hide
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: hide)
        }
    }

    @objc private func openLayoutMenu() {
        pendingHide?.cancel()
        menuOpen = true
        alphaValue = 1
        let menu = NSMenu(title: "Home Layout")
        menu.autoenablesItems = false
        for mode in HomeLayout.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(chooseLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == layout ? .on : .off
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        if layout == .cinematic {
            menu.addItem(.separator())
            for style in HomeHeroStyle.allCases {
                let item = NSMenuItem(title: style.title, action: #selector(chooseHero(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = style.rawValue
                item.state = style == heroStyle ? .on : .off
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY), in: self)
        menuOpen = false
        updateVisibility(topHovered)
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = HomeLayout(rawValue: raw) else { return }
        selectLayout?(mode)
    }

    @objc private func chooseHero(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = HomeHeroStyle(rawValue: raw) else { return }
        selectHero?(style)
    }

    deinit { pendingHide?.cancel() }
}
