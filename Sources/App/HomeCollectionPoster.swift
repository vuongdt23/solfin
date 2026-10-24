import SwiftUI
import JellyfinKit

/// Supporting poster or thumbnail, sized by its editorial canvas rather than
/// the ordinary shelf preference. An explicit height aligns responsive rows.
struct HomeCollectionPoster: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem
    var compact = false
    var showsFullArtwork = false
    var artworkHeight: CGFloat? = nil
    @State private var hovering = false

    private var artworkURL: URL? {
        if showsFullArtwork {
            return appState.api.primaryImageURL(for: item, maxHeight: nil)
                ?? appState.api.thumbnailImageURL(for: item, maxWidth: nil)
                ?? appState.api.backdropImageURL(for: item, maxWidth: nil)
        }
        return appState.api.thumbnailImageURL(for: item, maxWidth: 1200)
            ?? appState.api.backdropImageURL(for: item, maxWidth: 1200)
            ?? appState.api.primaryImageURL(for: item, maxHeight: 1000)
    }

    @ViewBuilder private var artworkCanvas: some View {
        if let artworkHeight {
            Color.white.opacity(0.04).frame(height: artworkHeight)
        } else {
            Color.white.opacity(0.04)
                .aspectRatio(showsFullArtwork ? 2 / 3 : 16 / 9, contentMode: .fit)
        }
    }

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 10) {
                artworkCanvas
                    .overlay {
                        CachedImage(url: artworkURL, contentMode: showsFullArtwork ? .fit : .fill)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 16))
                Text(item.name)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                    .frame(height: artworkHeight != nil ? 16 : nil, alignment: .leading)
                Text(item.productionYear.map(String.init) ?? (item.type == "Series" ? "Series" : "Movie"))
                    .font(.system(size: compact ? 10 : 12)).foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .frame(height: artworkHeight != nil ? 12 : nil, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .cardHoverEffect(isActive: hovering, lift: 5, scale: 1.025)
            .shadow(color: .black.opacity(hovering ? 0.3 : 0), radius: hovering ? 16 : 0, y: hovering ? 9 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(item.name). Open details")
    }
}
