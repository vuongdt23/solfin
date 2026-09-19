import SwiftUI
import JellyfinKit

// MARK: - Solar hero identity components

/// The logo/title lockup used by featured heroes and detail views.
struct SolarMediaLogo: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem
    var imageURL: URL? = nil
    var lookupDefaultLogo = true
    var maxWidth: CGFloat = 560
    var height: CGFloat = 170
    var fallbackSize: CGFloat = 74

    var body: some View {
        if let url = imageURL ?? (lookupDefaultLogo ? appState.api.logoImageURL(for: item) : nil) {
            CachedImage(url: url, contentMode: .fit)
                .frame(width: maxWidth, height: height, alignment: .leading)
                .accessibilityLabel("Logo for \(item.name)")
        } else {
            Text(item.name)
                .font(.system(size: fallbackSize, weight: .heavy, design: .rounded))
                .tracking(-2.2)
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct SolarContextLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.6)
            .foregroundStyle(SolfinDesign.Control.textMuted)
    }
}

struct SolarOfficialRatingBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel("Rating \(text)")
    }
}

struct SolarMediaMetadata: View {
    let item: BaseItem
    var episodeCode: String? = nil
    var runtime: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let episodeCode { metadataText(episodeCode) }
            if let year = item.productionYear { metadataText(String(year)) }
            if let runtime { metadataText(runtime) }
            if let rating = item.officialRating { SolarOfficialRatingBadge(text: rating) }
            if let score = item.communityRating {
                Label(String(format: "%.1f", score), systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SolfinDesign.solarGold)
                    .accessibilityLabel("Community rating \(String(format: "%.1f", score))")
            }
            if item.userData?.played == true {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(SolfinDesign.Control.text)
                    .accessibilityLabel("Played")
            }
        }
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(SolfinDesign.Control.text.opacity(0.92))
    }
}

struct SolarSeriesMetadata: View {
    let series: BaseItem
    let seasonCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let year = series.productionYear { metadataText(String(year)) }
            if let seasonCount { metadataText("\(seasonCount) season\(seasonCount == 1 ? "" : "s")") }
            if let rating = series.officialRating { SolarOfficialRatingBadge(text: rating) }
            if let score = series.communityRating {
                Label(String(format: "%.1f", score), systemImage: "star.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SolfinDesign.solarGold)
            }
            if let status = series.status, !status.isEmpty {
                Text(status)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(status.caseInsensitiveCompare("Continuing") == .orderedSame
                                     ? SolfinDesign.solarGold : SolfinDesign.Control.textMuted)
            }
        }
    }

    private func metadataText(_ value: String) -> some View {
        Text(value)
            .font(.callout.weight(.semibold))
            .foregroundStyle(SolfinDesign.Control.text.opacity(0.92))
    }
}

struct SolarGenreRow: View {
    let genres: [String]
    var body: some View {
        if !genres.isEmpty {
            Text(genres.prefix(3).joined(separator: "  ·  "))
                .font(.callout.weight(.bold))
                .foregroundStyle(SolfinDesign.Control.text.opacity(0.94))
        }
    }
}

struct SolarHeroOverview: View {
    let text: String
    var maxWidth: CGFloat = 820
    var lineLimit: Int? = 4

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .medium))
            .lineSpacing(4)
            .foregroundStyle(SolfinDesign.Control.text.opacity(0.94))
            .lineLimit(lineLimit)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

/// Complete reusable identity stack. The smaller components remain public within
/// the app module so detail pages and future hero variants can compose them.
struct SolarHeroIdentity<Actions: View>: View {
    let item: BaseItem
    var context: String?
    var episodeCode: String?
    var runtime: String?
    var overview: String?
    var logoURL: URL? = nil
    var logoWidth: CGFloat = 560
    var logoHeight: CGFloat = 170
    var fallbackSize: CGFloat = 74
    var lookupDefaultLogo = true
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            if let context { SolarContextLabel(text: context) }
            SolarMediaLogo(item: item, imageURL: logoURL, lookupDefaultLogo: lookupDefaultLogo, maxWidth: logoWidth, height: logoHeight, fallbackSize: fallbackSize)
            SolarMediaMetadata(item: item, episodeCode: episodeCode, runtime: runtime)
            if let genres = item.genres { SolarGenreRow(genres: genres) }
            if let overview { SolarHeroOverview(text: overview) }
            actions()
        }
        .shadow(color: .black.opacity(0.48), radius: 12, y: 3)
    }
}

struct SolarHeroActions<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { HStack(spacing: 12) { content() } }
}

/// A self-contained hero action that owns hover state, so adjacent buttons never
/// inherit one another's feedback state.
struct SolarHeroActionButton<Label: View>: View {
    let action: () -> Void
    let isPrimary: Bool
    let disabled: Bool
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    init(isPrimary: Bool = true, disabled: Bool = false, action: @escaping () -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.isPrimary = isPrimary
        self.disabled = disabled
        self.label = label
    }

    var body: some View {
        Button(action: action) { label() }
            .buttonStyle(SolarPillButtonStyle(hovering: hovering))
            .onHover { hovering = $0 }
            .disabled(disabled)
            .opacity(disabled ? 0.58 : 1)
            .animation(.easeOut(duration: 0.16), value: hovering)
    }
}
