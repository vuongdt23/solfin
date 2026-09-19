import SwiftUI

/// Shared visual language for every interactive control in the app.
/// Feature views should use these styles/modifiers rather than inline fills and borders.
struct SolarPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(SolfinDesign.Control.text)
            .padding(.horizontal, 16)
            .frame(minHeight: SolfinDesign.controlHeight)
            .background(configuration.isPressed ? SolfinDesign.Control.fillPressed : SolfinDesign.solarOrange.opacity(0.82), in: RoundedRectangle(cornerRadius: SolfinDesign.controlRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: SolfinDesign.controlRadius, style: .continuous).strokeBorder(configuration.isPressed ? SolfinDesign.solarGold : SolfinDesign.solarOrange.opacity(0.6), lineWidth: configuration.isPressed ? 2 : 1) }
            .shadow(color: configuration.isPressed ? SolfinDesign.Shadow.active.color : SolfinDesign.Shadow.control.color,
                    radius: configuration.isPressed ? SolfinDesign.Shadow.active.radius : SolfinDesign.Shadow.control.radius,
                    y: configuration.isPressed ? SolfinDesign.Shadow.active.y : SolfinDesign.Shadow.control.y)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct SolarSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(SolfinDesign.Control.text)
            .padding(.horizontal, 12)
            .frame(minHeight: SolfinDesign.controlHeight)
            .background(configuration.isPressed ? SolfinDesign.Control.fillPressed : SolfinDesign.Control.fill, in: RoundedRectangle(cornerRadius: SolfinDesign.controlRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: SolfinDesign.controlRadius, style: .continuous).strokeBorder(configuration.isPressed ? SolfinDesign.solarGold : SolfinDesign.Control.border) }
    }
}

struct SolarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? SolfinDesign.Control.text : SolfinDesign.Control.textMuted)
            .background(configuration.isPressed ? SolfinDesign.Control.fillPressed : SolfinDesign.Control.fill, in: Circle())
            .overlay { Circle().strokeBorder(configuration.isPressed ? SolfinDesign.solarGold : SolfinDesign.Control.border) }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct SolarField: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 13)
            .frame(height: SolfinDesign.controlHeight)
            .background(SolfinDesign.Control.fill, in: RoundedRectangle(cornerRadius: SolfinDesign.controlRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: SolfinDesign.controlRadius, style: .continuous).strokeBorder(SolfinDesign.Control.border) }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension View {
    func solarField() -> some View { modifier(SolarField()) }
}

struct SolarPillButtonStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? .white : .black)
            .background(hovering ? SolfinDesign.solarOrange.opacity(0.88) : .white, in: Capsule())
            .overlay {
                Capsule().strokeBorder(hovering || configuration.isPressed ? SolfinDesign.solarGold : .clear,
                                       lineWidth: configuration.isPressed ? 3 : 2)
            }
            .shadow(color: SolfinDesign.solarOrange.opacity(hovering || configuration.isPressed ? 0.42 : 0.16),
                    radius: hovering ? 20 : 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : hovering ? 1.035 : 1)
    }
}

struct SolarRoundButtonStyle: ButtonStyle {
    let hovering: Bool
    var idleFill: Color = .white.opacity(0.22)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(hovering || configuration.isPressed ? SolfinDesign.solarOrange.opacity(0.72) : idleFill, in: Circle())
            .overlay {
                Circle().strokeBorder(hovering || configuration.isPressed ? SolfinDesign.solarGold : .white.opacity(0.2),
                                      lineWidth: hovering || configuration.isPressed ? 2 : 1)
            }
            .shadow(color: SolfinDesign.solarOrange.opacity(hovering || configuration.isPressed ? 0.48 : 0.12),
                    radius: hovering ? 18 : 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.94 : hovering ? 1.08 : 1)
    }
}

struct SolarCardHoverGlow: View {
    let isHovering: Bool
    var radius: CGFloat = 180

    var body: some View {
        RoundedRectangle(cornerRadius: 21, style: .continuous)
            .fill(RadialGradient(colors: [SolfinDesign.solarOrange.opacity(0.34), SolfinDesign.solarRed.opacity(0.18), SolfinDesign.nebulaPurple.opacity(0.22), .clear], center: .center, startRadius: 10, endRadius: radius))
            .blur(radius: 16)
            .padding(-14)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(false)
    }
}

struct SolarToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [SolfinDesign.solarOrange.opacity(configuration.isPressed ? 0.34 : 0.18),
                                                  SolfinDesign.solarRed.opacity(configuration.isPressed ? 0.22 : 0.10),
                                                  SolfinDesign.nebulaPurple.opacity(configuration.isPressed ? 0.28 : 0.14)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .overlay { Capsule().strokeBorder(SolfinDesign.solarOrange.opacity(configuration.isPressed ? 0.5 : 0.26)) }
            }
            .shadow(color: SolfinDesign.solarOrange.opacity(configuration.isPressed ? 0.24 : 0.12), radius: 12, y: 5)
    }
}
