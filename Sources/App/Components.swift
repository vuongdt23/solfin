import SwiftUI
import JellyfinKit

/// Async poster image with a placeholder; uses AsyncImage (URLs already carry the token).
struct PosterImage: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                placeholder(systemName: "film")
            case .empty:
                if url == nil { placeholder(systemName: "film") }
                else { ZStack { Color.gray.opacity(0.15); ProgressView().controlSize(.small) } }
            @unknown default:
                placeholder(systemName: "film")
            }
        }
    }

    private func placeholder(systemName: String) -> some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: systemName).font(.largeTitle).foregroundStyle(.secondary)
        }
    }
}

/// Poster + label used in shelves and grids. Lifts and highlights on hover.
struct PosterCard: View {
    @EnvironmentObject var appState: AppState
    let item: BaseItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: appState.api.primaryImageURL(for: item))
                .frame(width: 160, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottom) { progressBar }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.tint, lineWidth: hovering ? 2.5 : 0)
                }
                .overlay {
                    if hovering {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white, .black.opacity(0.5))
                            .shadow(radius: 6)
                            .transition(.opacity)
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.35 : 0.15),
                        radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
                .scaleEffect(hovering ? 1.04 : 1.0)

            Text(item.name).font(.callout).lineLimit(1)
                .foregroundStyle(.primary.opacity(hovering ? 1.0 : 0.9))
            if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(width: 160)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }

    private var subtitle: String? {
        if item.type == "Episode" {
            let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
            let e = item.indexNumber.map { "E\($0)" } ?? ""
            return "\(item.seriesName ?? "") \(s)\(e)".trimmingCharacters(in: .whitespaces)
        }
        return item.productionYear.map(String.init)
    }

    @ViewBuilder
    private var progressBar: some View {
        if let pct = item.userData?.playedPercentage, pct > 0 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.4)).frame(height: 4)
                    Rectangle().fill(.tint).frame(width: geo.size.width * pct / 100, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

/// Full-width backdrop hero with a gradient scrim, used atop detail screens.
/// Falls back gracefully to a plain background when the item has no backdrop.
struct BackdropHero: View {
    let url: URL?
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.12)
                    }
                }
                .frame(height: height)
                .clipped()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35), Color(nsColor: .windowBackgroundColor)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: url == nil ? 0 : height)
    }
}

/// Persistent Now Playing strip pinned to the bottom of Home.
struct NowPlayingBar: View {
    @EnvironmentObject var nowPlaying: NowPlaying

    var body: some View {
        if nowPlaying.isActive, let name = nowPlaying.itemName {
            HStack(spacing: 16) {
                Image(systemName: nowPlaying.state == .paused ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.callout.bold()).lineLimit(1)
                    let detail = nowPlaying.subtitle.map { "\($0) · " } ?? ""
                    Text("\(detail)\(nowPlaying.state.rawValue) · \(timeString(nowPlaying.positionSeconds))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { nowPlaying.togglePause() } label: {
                    Image(systemName: "playpause.fill")
                }
                Button { nowPlaying.stop() } label: {
                    Image(systemName: "stop.fill")
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
