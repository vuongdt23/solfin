import SwiftUI
import JellyfinKit

enum SolfinDesign {
    static let pagePadding: CGFloat = 28
    static let sectionSpacing: CGFloat = 32
    static let posterRadius: CGFloat = 12
    static let controlRadius: CGFloat = 14
    static let accent = solarOrange
    static let solarOrange = Color(red: 1.0, green: 0.31, blue: 0.06)
    static let solarRed = Color(red: 0.95, green: 0.08, blue: 0.06)
    static let solarGold = Color(red: 1.0, green: 0.68, blue: 0.16)
    static let nebulaPurple = Color(red: 0.44, green: 0.08, blue: 0.68)
    static let spaceBlack = Color(red: 0.004, green: 0.004, blue: 0.012)

    static var solarBackground: some View { SolarThemeBackground() }
}

struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                             : AnyShapeStyle(.regularMaterial))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(reduceTransparency ? 0.18 : 0.12), lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

struct LoadingPosterGrid: View {
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: SolfinDesign.posterRadius)
                        .fill(.secondary.opacity(0.12))
                        .aspectRatio(2/3, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.12)).frame(height: 12)
                        .padding(.trailing, 24)
                }
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel("Loading media")
    }
}

struct EmptyContentView: View {
    let title: String
    let message: String
    var systemImage = "film.stack"
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let retry { Button("Try Again", action: retry) }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct MetadataPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }
}
