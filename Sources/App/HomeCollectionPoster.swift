import SwiftUI
import JellyfinKit

/// Supporting poster in the collection's editorial block, sized by its canvas
/// rather than the ordinary shelf preference.
struct HomeCollectionPoster: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem
    let height: CGFloat

    var body: some View {
        NavigationLink(value: item) {
            VStack(alignment: .leading, spacing: 10) {
                Color.white.opacity(0.04)
                    .overlay {
                        CachedImage(url: appState.api.primaryImageURL(for: item, maxHeight: 1000))
                    }
                    .frame(height: height - 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                Text(item.productionYear.map(String.init) ?? (item.type == "Series" ? "Series" : "Movie"))
                    .font(.caption).foregroundStyle(.white.opacity(0.56))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name). Open details")
    }
}
