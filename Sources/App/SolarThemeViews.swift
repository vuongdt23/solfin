import SwiftUI
import JellyfinKit

struct SolarThemeBackground: View {
    var body: some View {
        ZStack {
            SolfinDesign.spaceBlack
            LinearGradient(colors: [Color.black,
                                    SolfinDesign.spaceBlack,
                                    Color.black,
                                    SolfinDesign.nebulaPurple.opacity(0.05)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            RadialGradient(colors: [SolfinDesign.solarOrange.opacity(0.14),
                                    SolfinDesign.solarRed.opacity(0.05),
                                    .clear],
                           center: UnitPoint(x: 0.96, y: 0.08),
                           startRadius: 0,
                           endRadius: 720)
            RadialGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.14),
                                    SolfinDesign.nebulaPurple.opacity(0.04),
                                    .clear],
                           center: UnitPoint(x: 0.12, y: 0.92),
                           startRadius: 20,
                           endRadius: 820)
            LiquidGlassVeil()
            SolarStarField()
        }
        .ignoresSafeArea()
    }
}

private struct LiquidGlassVeil: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(SolfinDesign.solarOrange.opacity(0.08))
                    .frame(width: proxy.size.width * 0.38, height: proxy.size.height * 0.22)
                    .blur(radius: 70)
                    .rotationEffect(.degrees(-18))
                    .position(x: proxy.size.width * 0.86, y: proxy.size.height * 0.18)
                Capsule()
                    .fill(SolfinDesign.nebulaPurple.opacity(0.10))
                    .frame(width: proxy.size.width * 0.52, height: proxy.size.height * 0.24)
                    .blur(radius: 82)
                    .rotationEffect(.degrees(16))
                    .position(x: proxy.size.width * 0.25, y: proxy.size.height * 0.82)
                Rectangle()
                    .fill(.white.opacity(0.018))
                    .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SolarStarField: View {
    private let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.08, 0.14, 1.1, 0.38), (0.16, 0.34, 0.8, 0.28), (0.26, 0.12, 0.9, 0.32),
        (0.38, 0.22, 1.2, 0.42), (0.48, 0.08, 0.8, 0.3), (0.58, 0.34, 1.0, 0.32),
        (0.72, 0.19, 0.8, 0.28), (0.84, 0.38, 1.0, 0.25), (0.94, 0.16, 0.8, 0.24),
        (0.12, 0.72, 0.9, 0.26), (0.32, 0.86, 1.1, 0.3), (0.52, 0.74, 0.8, 0.24),
        (0.68, 0.88, 1.0, 0.28), (0.82, 0.68, 0.8, 0.22), (0.96, 0.82, 1.1, 0.26)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(stars.indices, id: \.self) { index in
                let star = stars[index]
                Circle()
                    .fill(.white.opacity(star.opacity))
                    .frame(width: star.size, height: star.size)
                    .position(x: proxy.size.width * star.x, y: proxy.size.height * star.y)
            }
        }
        .allowsHitTesting(false)
    }
}

struct IntegratedSolarSidebar: View {
    let selection: AppDestination?
    let libraries: [BaseItem]
    @Binding var isExpanded: Bool
    let navigate: (AppDestination) -> Void
    let icon: (BaseItem) -> String

    private var width: CGFloat { isExpanded ? 210 : 64 }

    var body: some View {
        VStack(spacing: 18) {
            expandButton
            VStack(spacing: 14) {
                navButton("Home", systemImage: "house.fill", destination: .home)
                navButton("Search", systemImage: "magnifyingglass", destination: .search)
            }
            if isExpanded && !libraries.isEmpty {
                Text("LIBRARIES")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.34))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
            VStack(spacing: 14) {
                ForEach(libraries) { library in
                    navButton(library.name, systemImage: icon(library), destination: .library(library.id))
                }
            }
            Spacer(minLength: 16)
            SettingsLink { sidebarLabel("Settings", systemImage: "gearshape.fill", selected: false) }
                .buttonStyle(.plain)
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
        .padding(.horizontal, 8)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                // Keep the hero artwork visible beneath the navigation, while the
                // dark scrim preserves icon and label contrast.
                Color.black.opacity(isExpanded ? 0.52 : 0.30)
                LinearGradient(colors: [SolfinDesign.spaceBlack.opacity(0.56), .clear, SolfinDesign.nebulaPurple.opacity(0.10)],
                               startPoint: .leading,
                               endPoint: .trailing)
                Rectangle().fill(.ultraThinMaterial).opacity(isExpanded ? 0.12 : 0.06)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isExpanded)
    }

    private var expandButton: some View {
        Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { isExpanded.toggle() } } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [SolfinDesign.solarGold, SolfinDesign.solarOrange, SolfinDesign.nebulaPurple.opacity(0.55)],
                                             center: .topLeading, startRadius: 1, endRadius: 24))
                    Image(systemName: isExpanded ? "sidebar.left" : "line.3.horizontal")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                if isExpanded {
                    Text("Solfin")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse sidebar" : "Expand sidebar")
    }

    private func navButton(_ title: String, systemImage: String, destination: AppDestination) -> some View {
        let selected = selection == destination
        return Button { navigate(destination) } label: {
            sidebarLabel(title, systemImage: systemImage, selected: selected)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func sidebarLabel(_ title: String, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
            if isExpanded {
                Text(title)
                    .font(.callout.weight(selected ? .bold : .semibold))
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(selected ? .white : .white.opacity(0.74))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: 42)
        .contentShape(Rectangle())
        .background {
            if selected {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().fill(LinearGradient(colors: [SolfinDesign.solarOrange.opacity(0.50),
                                                               SolfinDesign.solarRed.opacity(0.30),
                                                               SolfinDesign.nebulaPurple.opacity(0.42)],
                                                      startPoint: .topLeading,
                                                      endPoint: .bottomTrailing))
                    }
                    .overlay { Capsule().strokeBorder(SolfinDesign.solarGold.opacity(0.44)) }
                    .shadow(color: SolfinDesign.solarOrange.opacity(0.24), radius: 18, y: 5)
                    .shadow(color: SolfinDesign.nebulaPurple.opacity(0.20), radius: 22, y: 8)
            }
        }
    }
}
