import SwiftUI

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
