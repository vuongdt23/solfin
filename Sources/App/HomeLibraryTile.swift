import SwiftUI
import JellyfinKit
import PlaybackEngine

/// A library's identity stays separate from its artwork: randomized posters form a
/// small collection on the right, never a second baked-in library title.
struct HomeLibraryTile: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: BaseItem
    let posters: [BaseItem]
    var width: CGFloat = 480
    @State private var hovering = false

    private var height: CGFloat { width * 0.52 }
    private var posterWidth: CGFloat { height * 0.49 }
    private var posterHeight: CGFloat { posterWidth * 1.5 }
    private var cornerRadius: CGFloat { 22 }

    private var icon: String {
        switch item.collectionType?.lowercased() {
        case "movies": return "film"
        case "tvshows": return "tv"
        default: return "rectangle.stack"
        }
    }

    private var accent: Color {
        item.collectionType?.lowercased() == "tvshows"
            ? Color(red: 0.72, green: 0.56, blue: 0.96) : SolfinDesign.solarGold
    }

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.065, green: 0.062, blue: 0.08))
                LinearGradient(colors: [.clear, accent.opacity(hovering ? 0.14 : 0.07)],
                               startPoint: .leading, endPoint: .trailing)
                posterStack
                    .offset(y: hovering && !reduceMotion ? -3 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(accent)
                    Text(item.name)
                        .font(.system(size: width >= 460 ? 34 : 30, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        Text("Explore library")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(hovering ? 0.86 : 0.6))
                }
                .frame(width: width * 0.4, alignment: .leading)
                .padding(.leading, width * 0.07)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(hovering ? SolfinDesign.solarGold.opacity(0.75) : .white.opacity(0.12))
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Browse \(item.name)")
        .help("Open \(item.name)")
    }

    private var posterStack: some View {
        ZStack {
            // Draw back to front, with the first random title in the foreground.
            ForEach((0..<3).reversed(), id: \.self) { index in
                LibraryTilePoster(url: posters.indices.contains(index)
                                  ? appState.api.primaryImageURL(for: posters[index], maxHeight: 640)
                                  : nil, icon: icon, accent: accent)
                    .frame(width: posterWidth, height: posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2)) }
                    .shadow(color: .black.opacity(0.5), radius: 12, x: -6, y: 8)
                    .rotationEffect(.degrees(Double(index - 1) * (hovering && !reduceMotion ? 13 : 10)))
                    .position(x: width * (0.655 + CGFloat(index) * 0.085),
                              y: height * (index == 1 ? 0.5 : 0.54))
            }
        }
        .frame(width: width, height: height)
    }
}

/// Quiet placeholders rather than three spinners while cached images load.
private struct LibraryTilePoster: View {
    let url: URL?
    let icon: String
    let accent: Color
    @State private var image: NSImage?

    var body: some View {
        LinearGradient(colors: [accent.opacity(0.24), Color(red: 0.1, green: 0.08, blue: 0.15)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(accent.opacity(0.5))
                }
            }
            .clipped()
            .task(id: url) {
                image = nil
                guard let url else { return }
                let loaded = await MediaAssetCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}
