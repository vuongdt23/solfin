import SwiftUI

struct HomeLayoutMenu: View {
    @Binding var layoutRaw: String
    @Binding var heroStyleRaw: String
    let isTopHovered: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isKeyboardFocused: Bool
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    private var layout: HomeLayout { HomeLayout.saved(layoutRaw) }

    var body: some View {
        Menu {
            Picker("Home Layout", selection: $layoutRaw) {
                ForEach(HomeLayout.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                }
            }
            if layout == .cinematic {
                Divider()
                Picker("Cinematic Hero", selection: $heroStyleRaw) {
                    ForEach(HomeHeroStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
        } label: {
            Label("Home Layout", systemImage: "rectangle.3.group")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.black.opacity(0.62), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.18)) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .focused($isKeyboardFocused)
        .accessibilityFocused($isAccessibilityFocused)
        // Reveal across the page's top band, and retain direct button hover
        // plus keyboard/VoiceOver access without intercepting artwork clicks.
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .opacity(isTopHovered || isHovered || isKeyboardFocused || isAccessibilityFocused ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isTopHovered || isHovered)
        .foregroundStyle(.white)
        .help("Choose your home layout (currently \(layout.title))")
        .accessibilityLabel("Home Layout: \(layout.title)")
    }
}
