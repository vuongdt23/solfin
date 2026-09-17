import SwiftUI

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
