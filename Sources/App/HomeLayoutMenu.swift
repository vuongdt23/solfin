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
        title = "Home Layout"
        bezelStyle = .rounded
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 13, weight: .semibold)
        contentTintColor = .white
        target = self
        action = #selector(openLayoutMenu)
        setAccessibilityLabel("Home Layout")
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 36) }

    // Only the menu mechanics are native. Draw the original quiet dark pill
    // instead of letting NSButton introduce a standard macOS bezel.
    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.black.withAlphaComponent(cell?.isHighlighted == true ? 0.78 : 0.62).setFill()
        pill.fill()
        let focused = window?.firstResponder === self
        NSColor.white.withAlphaComponent(focused ? 0.55 : 0.18).setStroke()
        pill.lineWidth = focused ? 2 : 1
        pill.stroke()

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) {
            drawWhiteSymbol(symbol, in: NSRect(x: 13, y: (bounds.height - 15) / 2, width: 17, height: 15))
        }
        let text = NSAttributedString(string: "Home Layout", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
        text.draw(at: NSPoint(x: 37, y: (bounds.height - text.size().height) / 2))
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)) {
            drawWhiteSymbol(chevron, in: NSRect(x: bounds.width - 22, y: (bounds.height - 7) / 2,
                                              width: 9, height: 7))
        }
    }

    private func drawWhiteSymbol(_ image: NSImage, in rect: NSRect) {
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: rect)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { pendingHide?.cancel(); alphaValue = 1; needsDisplay = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { updateVisibility(topHovered); needsDisplay = true }
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
