import SwiftUI
import JellyfinKit

struct FolderCard: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem

    private var artworkURL: URL? {
        appState.api.thumbnailImageURL(for: item, maxWidth: 1000)
            ?? appState.api.backdropImageURL(for: item, maxWidth: 1000)
            ?? appState.api.primaryImageURL(for: item, maxHeight: 560)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.075, green: 0.08, blue: 0.11))
                if let artworkURL {
                    CachedImage(url: artworkURL, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    folderPlaceholder
                }
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SolfinDesign.solarGold)
                    .padding(9)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 9))
                    .padding(10)
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)) }
            .cardHoverEffect(lift: 4, scale: 1.015)

            HStack(spacing: 8) {
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count = item.childCount ?? item.recursiveItemCount {
                    Text("\(count) items")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open \(item.name)")
        .help("Open \(item.name)")
    }

    private var folderPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.17), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "folder.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(SolfinDesign.solarGold.opacity(0.8))
        }
    }
}
