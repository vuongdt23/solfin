import SwiftUI
import JellyfinKit
import PlaybackEngine

/// Fixed artwork canvas: images cannot grow the page or move its controls.
struct HomeFeatureArtwork: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem

    var body: some View {
        GeometryReader { proxy in
            let url = item.type == "Episode"
                ? appState.api.episodeArtworkURL(for: item, maxWidth: 1600)
                : appState.api.backdropImageURL(for: item, maxWidth: 2400)
                    ?? appState.api.primaryImageURL(for: item, maxHeight: 1200)
            SolfinDesign.spaceBlack
                .overlay { FaceAwareHeroArtwork(url: url, size: proxy.size) }
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.04), location: 0),
                        .init(color: .black.opacity(0.2), location: 0.35),
                        .init(color: .black.opacity(0.92), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .clipped()
        }
        .accessibilityHidden(true)
    }
}

struct HomeSectionTitle: View {
    let title: String
    var eyebrow: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow { SolarContextLabel(text: eyebrow) }
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct HomePlaybackAction: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let item: BaseItem
    var title: String = "Play"
    var prominent = false
    @State private var hovering = false
    @State private var resolvingSeries = false

    var body: some View {
        Button {
            Task { await play() }
        } label: {
            Label(resolvingSeries ? "Finding episode…" : title, systemImage: "play.fill")
                .font(.system(size: prominent ? 17 : 15, weight: .bold))
                .padding(.horizontal, prominent ? 28 : 22)
                .frame(height: prominent ? 52 : 46)
        }
        .buttonStyle(SolarPillButtonStyle(hovering: hovering))
        .onHover { hovering = $0 }
        .disabled(resolvingSeries || item.isOffline)
        .accessibilityLabel("\(title) \(item.name)")
    }

    @MainActor private func play() async {
        appState.playbackError = nil
        if item.type == "Series" {
            resolvingSeries = true
            defer { resolvingSeries = false }
            do {
                let episodes = try await appState.api.episodes(seriesId: item.id)
                let available = episodes.filter { !$0.isOffline }
                guard let episode = available.first(where: { HomePresentation.progress($0) != nil })
                        ?? available.first(where: { $0.userData?.played != true }) ?? available.first else {
                    appState.playbackError = "No playable episodes are available for this series."
                    return
                }
                nowPlaying.play(item: episode, api: appState.api, config: appState.makePlaybackConfig(),
                                queue: available, queueIndex: available.firstIndex(where: { $0.id == episode.id })) {
                    appState.playbackError = $0
                }
            } catch { appState.playbackError = error.localizedDescription }
        } else {
            nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig()) {
                appState.playbackError = $0
            }
        }
    }
}

struct HomeDetailsAction: View {
    let item: BaseItem
    var prominent = false
    @State private var hovering = false
    var body: some View {
        NavigationLink(value: item) {
            Label("Details", systemImage: "info.circle")
                .font(.system(size: prominent ? 17 : 14, weight: .semibold))
                .padding(.horizontal, prominent ? 22 : 18)
                .frame(height: prominent ? 52 : 46)
                .background(.white.opacity(hovering ? 0.24 : 0.12), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(hovering ? 0.5 : 0.18)) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .onHover { hovering = $0 }
        .accessibilityLabel("Details for \(item.name)")
    }
}

struct HomeProgressIdentity: View {
    let item: BaseItem
    var body: some View {
        if let progress = HomePresentation.progress(item) {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .tint(SolfinDesign.solarGold)
                    .accessibilityLabel("Viewing progress for \(item.name)")
                if let remaining = HomePresentation.remaining(item) {
                    Text(remaining).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }
}

/// Editorial tile; this is navigation, never a nested play button inside a link.
struct HomeEditorialTile: View {
    let item: BaseItem
    let context: String
    let height: CGFloat
    var prominent = false
    @State private var hovering = false

    var body: some View {
        NavigationLink(value: item) {
            HomeFeatureArtwork(item: item)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: prominent ? 12 : 8) {
                        SolarContextLabel(text: context)
                        Text(item.type == "Episode" ? item.seriesName ?? item.name : item.name)
                            .font(.system(size: prominent ? 32 : 21, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let episode = HomePresentation.episodeIdentity(item) {
                            Text(episode).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                        } else if let year = item.productionYear {
                            Text(String(year)).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                        }
                        if prominent, let overview = item.overview {
                            Text(overview).font(.system(size: 15)).foregroundStyle(.white.opacity(0.76)).lineLimit(2)
                        }
                        HStack {
                            Text("Explore title").font(.caption.weight(.semibold))
                            Image(systemName: "arrow.up.right").font(.caption.bold())
                        }
                        .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(prominent ? 28 : 20)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .cardHoverEffect(isActive: hovering, lift: 6, scale: 1.025)
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(context): \(item.name). Open details")
    }
}

struct HomeRecentComposition: View {
    let items: [BaseItem]
    let geometry: HomeRecentGeometry

    private var supporting: [BaseItem] { Array(items.dropFirst().prefix(geometry.supportingCount)) }

    var body: some View {
        if let lead = items.first {
            let layout = geometry.sideBySide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: HomeRecentGeometry.sectionSpacing))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: HomeRecentGeometry.sectionSpacing))
            layout {
                HomeEditorialTile(item: lead, context: "Recently added",
                                  height: geometry.leadHeight, prominent: true)
                    .frame(width: geometry.leadWidth)
                if !supporting.isEmpty { supportingGrid }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var supportingGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(geometry.cardWidth),
                                                spacing: HomeRecentGeometry.cardSpacing),
                            count: geometry.columns)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: HomeRecentGeometry.cardSpacing) {
            ForEach(supporting) { item in
                HomeCollectionPoster(item: item, compact: true,
                                     showsFullArtwork: geometry.artwork == .poster,
                                     artworkHeight: geometry.artworkHeight)
                    .frame(width: geometry.cardWidth, alignment: .leading)
            }
        }
        .frame(width: geometry.supportingWidth, alignment: .leading)
    }
}

struct HomeEditorialComposition: View {
    let items: [BaseItem]
    let availableWidth: CGFloat
    let context: String
    var posterSupport = false
    var body: some View {
        if let first = items.first {
            if availableWidth >= 880 && items.count > 1 {
                HStack(alignment: .top, spacing: 18) {
                    HomeEditorialTile(item: first, context: context, height: 420, prominent: true)
                        .frame(width: (availableWidth - 18) * 0.63)
                    if posterSupport {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(Array(items.dropFirst().prefix(2))) { item in
                                HomeCollectionPoster(item: item)
                            }
                        }
                    } else {
                        VStack(spacing: 18) {
                            ForEach(Array(items.dropFirst().prefix(2))) { item in
                                HomeEditorialTile(item: item, context: context, height: items.count > 2 ? 201 : 420)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 18) {
                    HomeEditorialTile(item: first, context: context, height: 360, prominent: true)
                    if items.count > 1 {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: min(280, availableWidth)))], spacing: 18) {
                            ForEach(Array(items.dropFirst().prefix(2))) { item in
                                if posterSupport { HomeCollectionPoster(item: item) }
                                else { HomeEditorialTile(item: item, context: context, height: 220) }
                            }
                        }
                    }
                }
            }
        }
    }
}
