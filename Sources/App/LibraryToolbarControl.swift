import SwiftUI

/// Quiet at rest, with the library's solar/fiery feedback on hover and keyboard focus.
/// Applied to the actual Menu/Button so the entire padded surface remains clickable.
struct LibraryToolbarControl: ViewModifier {
    var isActive = false
    var tracksHover = true
    @State private var hovering = false
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highlighted: Bool { tracksHover && (hovering || focused) }

    func body(content: Content) -> some View {
        content
            .font(.callout.weight(.medium))
            .foregroundStyle(isActive || highlighted ? SolfinDesign.solarGold : .white.opacity(0.86))
            .tint(isActive || highlighted ? SolfinDesign.solarGold : .white.opacity(0.86))
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [SolfinDesign.solarOrange.opacity(highlighted ? 0.22 : (isActive ? 0.1 : 0)),
                                                          SolfinDesign.solarRed.opacity(highlighted ? 0.14 : 0),
                                                          SolfinDesign.nebulaPurple.opacity(highlighted ? 0.18 : 0)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(highlighted ? AnyShapeStyle(LinearGradient(
                                colors: [SolfinDesign.solarGold, SolfinDesign.solarOrange, SolfinDesign.nebulaPurple],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(isActive ? SolfinDesign.solarOrange.opacity(0.45) : .white.opacity(0.1)),
                                          lineWidth: focused ? 2 : 1)
                    }
                    .allowsHitTesting(false)
            }
            .shadow(color: SolfinDesign.solarOrange.opacity(highlighted ? 0.2 : 0), radius: 12, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            // Native Menu controls can dismiss/reopen while their trigger is being
            // invalidated by hover-state changes. Keep menu labels visually stable;
            // hover feedback remains enabled for ordinary buttons.
            .onHover { if tracksHover { hovering = $0 } }
            .animation(tracksHover && !reduceMotion ? .easeOut(duration: 0.16) : nil, value: hovering)
    }
}
