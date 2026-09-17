import SwiftUI
import JellyfinKit

struct SeriesDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let series: BaseItem

    @State private var seasons: [BaseItem] = []
    @State private var selectedSeasonId: String?
    @State private var episodes: [BaseItem] = []
    @State private var loadError: String?
    @State private var loadingEpisodes = false
    @State private var episodeLoadID = UUID()
    @State private var overviewExpanded = false
    @State private var heroAvailableWidth: CGFloat = 1600

    var body: some View {
        ScrollView {
            seriesHero
        }
        .background(SolfinDesign.solarBackground)
        .navigationTitle(series.name)
        .task { await loadSeasons() }
    }

    private var seriesHero: some View {
        ZStack(alignment: .top) {
            seriesBackdrop

            // All of the series content shares the artwork canvas. The stack is
            // intentionally allowed to outgrow the 16:9 backdrop on smaller
            // windows, so the episode shelf can continue naturally into a short
            // scroll instead of being clipped inside the hero.
            VStack(alignment: .leading, spacing: 28) {
                heroCopy(availableWidth: heroAvailableWidth)
                if !seasons.isEmpty { seasonsShelf }
                episodeHeader
                episodeContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.top, 64)
            .padding(.bottom, 70)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: SeriesHeroWidthKey.self, value: proxy.size.width)
                }
            }
        }
        .background(SolfinDesign.solarBackground)
        .onPreferenceChange(SeriesHeroWidthKey.self) { width in
            guard width > 0, abs(width - heroAvailableWidth) > 1 else { return }
            heroAvailableWidth = width
        }
    }

    private var seriesBackdrop: some View {
        ZStack {
            Color.black
            if let url = appState.api.backdropImageURL(for: series, maxWidth: nil) {
                CachedImage(url: url, contentMode: .fit)
            } else {
                LinearGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.38), SolfinDesign.spaceBlack],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            ZStack {
                RadialGradient(colors: [SolfinDesign.solarGold.opacity(0.62), SolfinDesign.solarOrange.opacity(0.3), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 760)
                RadialGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.34), .clear],
                               center: .bottomLeading, startRadius: 40, endRadius: 780)
            }
            .blendMode(.screen)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.16), location: 0),
                .init(color: .clear, location: 0.30),
                .init(color: SolfinDesign.spaceBlack.opacity(0.28), location: 0.62),
                .init(color: SolfinDesign.spaceBlack.opacity(0.98), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.42), .clear, .black.opacity(0.08)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private func heroCopy(availableWidth: CGFloat) -> some View {
        let contentWidth = max(0, availableWidth - 76)
        let copyWidth = min(820, max(220, contentWidth * 0.58))
        return VStack(alignment: .leading, spacing: 15) {
            FeaturedTitleView(item: series, availableWidth: copyWidth)
            heroMetadata
            if let genres = series.genres, !genres.isEmpty {
                Text(genres.prefix(4).joined(separator: "  ·  "))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let overview = series.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(overviewExpanded ? nil : 3)
                    .frame(maxWidth: min(760, availableWidth * 0.42), alignment: .leading)
                if overview.count > 380 {
                    Button(overviewExpanded ? "Show Less" : "More") { withAnimation { overviewExpanded.toggle() } }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            if let episode = defaultPlaybackEpisode {
                Button { play(episode, startOver: false, queue: allQueuedEpisodes,
                              queueIndex: allQueuedEpisodes.firstIndex(where: { $0.id == episode.id })) } label: {
                    Label(playLabel(for: episode), systemImage: "play.fill")
                        .padding(.horizontal, 8).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
        .frame(maxWidth: copyWidth, alignment: .leading)
    }

    private var heroMetadata: some View {
        HStack(spacing: 10) {
            if let year = series.productionYear { heroPill(String(year)) }
            if let count = seasonCount { heroPill("\(count) season\(count == 1 ? "" : "s")") }
            if let official = series.officialRating { heroPill(official) }
            if let rating = series.communityRating {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            if let status = series.status, !status.isEmpty {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.caseInsensitiveCompare("Continuing") == .orderedSame
                                     ? SolfinDesign.solarGold : .white.opacity(0.78))
            }
        }
    }

    private var seasonsShelf: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Seasons").font(.title3.weight(.semibold))
                    if let season = selectedSeason, let summary = seasonSummary(season) {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(seasons) { season in
                        SeasonCard(season: season, selected: season.id == selectedSeasonId,
                                   onSelect: {
                                       guard selectedSeasonId != season.id else { return }
                                       selectedSeasonId = season.id
                                       Task { await loadEpisodes(seasonId: season.id) }
                                   },
                                   onPlay: { Task { await playSeason(season) } })
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
        .padding(.top, 2)
    }

    private var episodeHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSeason?.name ?? "Episodes").font(.title3.weight(.semibold))
                if !episodes.isEmpty {
                    Text(episodeHeaderSummary).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if loadingEpisodes && !episodes.isEmpty {
                ProgressView().controlSize(.small).tint(SolfinDesign.solarOrange)
            }
        }
    }

    @ViewBuilder private var episodeContent: some View {
        if loadingEpisodes && episodes.isEmpty { episodeSkeleton }
        else if let loadError, episodes.isEmpty {
            EmptyContentView(title: "Episodes unavailable", message: loadError, systemImage: "wifi.exclamationmark") {
                if let selectedSeasonId { Task { await loadEpisodes(seasonId: selectedSeasonId) } }
            }
        } else if episodes.isEmpty {
            EmptyContentView(title: "No episodes", message: "This season does not contain any episodes.")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 430), spacing: 18, alignment: .top)],
                      alignment: .leading, spacing: 22) {
                ForEach(episodes) { episode in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink(value: episode) { EpisodeCard(episode: episode) }
                            .buttonStyle(.plain)
                        WatchedToggle(isPlayed: episode.userData?.played == true) { played in
                            Task { await setPlayed(episode, played: played) }
                        }
                    }
                    .contextMenu {
                        Button(resumeSeconds(episode) > 0 ? "Resume" : "Play") {
                            playEpisodeFromGrid(episode, startOver: false)
                        }
                        if resumeSeconds(episode) > 0 {
                            Button("Start Over") { playEpisodeFromGrid(episode, startOver: true) }
                        }
                        Divider()
                        Button(episode.userData?.played == true ? "Mark Unwatched" : "Mark Watched") {
                            Task { await setPlayed(episode, played: episode.userData?.played != true) }
                        }
                    }
                }
            }
            .opacity(loadingEpisodes ? 0.55 : 1)
        }
    }

    private var episodeSkeleton: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 430), spacing: 18, alignment: .top)], spacing: 22) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 13).fill(.secondary.opacity(0.12)).aspectRatio(16/9, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.12)).frame(width: 220, height: 17)
                    RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.08)).frame(height: 12)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var selectedSeason: BaseItem? { seasons.first { $0.id == selectedSeasonId } }
    private var seasonCount: Int? { seasons.isEmpty ? series.childCount : seasons.count }
    private var episodeHeaderSummary: String {
        let unplayed = selectedSeason?.userData?.unplayedItemCount
        if let unplayed, unplayed > 0 { return "\(episodes.count) episodes · \(unplayed) unwatched" }
        return "\(episodes.count) episodes"
    }
    private var defaultPlaybackEpisode: BaseItem? {
        episodes.first { resumeSeconds($0) > 0 }
            ?? episodes.first { $0.userData?.played != true }
            ?? episodes.first
    }
    private var allQueuedEpisodes: [BaseItem] { episodes }

    private func seasonSummary(_ season: BaseItem) -> String? {
        var values: [String] = []
        if let year = season.productionYear { values.append(String(year)) }
        if let unplayed = season.userData?.unplayedItemCount, unplayed > 0 {
            values.append("\(unplayed) unwatched")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func heroPill(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.black.opacity(0.3), in: Capsule())
    }
    private func resumeSeconds(_ episode: BaseItem) -> Double { Ticks.toSeconds(episode.userData?.playbackPositionTicks) }
    private func playLabel(for episode: BaseItem) -> String { resumeSeconds(episode) > 0 ? "Resume" : "Play" }
    private func playEpisodeFromGrid(_ episode: BaseItem, startOver: Bool) {
        let q = allQueuedEpisodes
        play(episode, startOver: startOver, queue: q, queueIndex: q.firstIndex(where: { $0.id == episode.id }))
    }
    private func playSeason(_ season: BaseItem) async {
        appState.playbackError = nil
        do {
            let seasonEpisodes = try await appState.api.episodes(seriesId: series.id, seasonId: season.id)
            guard let first = seasonEpisodes.first(where: { resumeSeconds($0) > 0 })
                    ?? seasonEpisodes.first(where: { $0.userData?.played != true })
                    ?? seasonEpisodes.first else { return }
            selectedSeasonId = season.id
            episodes = seasonEpisodes
            play(first, startOver: false, queue: seasonEpisodes,
                 queueIndex: seasonEpisodes.firstIndex(where: { $0.id == first.id }))
        } catch {
            appState.playbackError = error.localizedDescription
        }
    }
    private func play(_ episode: BaseItem, startOver: Bool, queue: [BaseItem] = [], queueIndex: Int? = nil) {
        appState.playbackError = nil
        nowPlaying.play(item: episode, api: appState.api, config: appState.makePlaybackConfig(),
                        startOver: startOver, queue: queue, queueIndex: queueIndex) { appState.playbackError = $0 }
    }
    private func setPlayed(_ episode: BaseItem, played: Bool) async {
        do {
            try await appState.api.setPlayed(itemId: episode.id, played: played)
            guard let selectedSeasonId else { return }
            await loadEpisodes(seasonId: selectedSeasonId)
            seasons = try await appState.api.seasons(seriesId: series.id)
        } catch {
            loadError = error.localizedDescription
        }
    }
    private func loadSeasons() async {
        loadError = nil
        do {
            seasons = try await appState.api.seasons(seriesId: series.id)
            if let first = seasons.first {
                selectedSeasonId = first.id
                await loadEpisodes(seasonId: first.id)
            }
        } catch { loadError = error.localizedDescription }
    }
    private func loadEpisodes(seasonId: String) async {
        let requestID = UUID(); episodeLoadID = requestID; loadingEpisodes = true; loadError = nil
        do {
            let loaded = try await appState.api.episodes(seriesId: series.id, seasonId: seasonId)
            guard requestID == episodeLoadID, selectedSeasonId == seasonId else { return }
            episodes = loaded
        } catch {
            guard requestID == episodeLoadID else { return }
            loadError = error.localizedDescription
        }
        if requestID == episodeLoadID { loadingEpisodes = false }
    }
}

private struct SeriesHeroWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FeaturedTitleView: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem
    let availableWidth: CGFloat

    private var logoWidth: CGFloat { min(820, max(480, availableWidth * 0.44)) }
    private var logoHeight: CGFloat { min(230, max(150, availableWidth * 0.14)) }
    private var fallbackSize: CGFloat { min(70, max(48, availableWidth * 0.042)) }

    var body: some View {
        if let url = appState.api.logoImageURL(for: item, maxWidth: 1400) {
            CachedImage(url: url, contentMode: .fit)
                .frame(width: logoWidth, height: logoHeight, alignment: .leading)
        } else { fallback }
    }
    private var fallback: some View {
        Text(item.name).font(.system(size: fallbackSize, weight: .bold, design: .rounded)).tracking(-1.4)
            .foregroundStyle(.white).lineLimit(2).frame(maxWidth: min(860, availableWidth * 0.48), alignment: .leading)
    }
}

private struct SeasonCard: View {
    @EnvironmentObject private var appState: AppState
    let season: BaseItem
    let selected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    @State private var hovering = false
    @State private var playHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                PosterImage(url: appState.api.primaryImageURL(for: season, maxHeight: 420))
                    .frame(width: 170, height: 255).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().fill(playHovering ? SolfinDesign.solarOrange.opacity(0.88) : .clear) }
                            .overlay { Circle().strokeBorder(playHovering ? SolfinDesign.solarGold : .white.opacity(0.72), lineWidth: playHovering ? 2 : 1.5) }
                            .shadow(color: .black.opacity(playHovering ? 0.55 : 0.35), radius: playHovering ? 14 : 9, y: 5)
                            .scaleEffect(playHovering ? 1.1 : 1)
                    }
                    .buttonStyle(.plain)
                    .help("Play season")
                    .accessibilityLabel("Play \(season.name)")
                    .onHover { playHovering = $0 }
                    .animation(.easeOut(duration: 0.16), value: playHovering)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .animation(.easeOut(duration: 0.16), value: hovering)
            }
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? AnyShapeStyle(LinearGradient(colors: [SolfinDesign.solarOrange, SolfinDesign.solarRed, SolfinDesign.nebulaPurple], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(.white.opacity(0.1)), lineWidth: selected ? 3 : 1) }
            Text(season.name).font(.system(size: 17, weight: selected ? .semibold : .regular)).foregroundStyle(.white).lineLimit(1)
            if let count = season.childCount { Text("\(count) episodes").font(.caption).foregroundStyle(.white.opacity(0.58)) }
        }
        .frame(width: 170, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

private struct EpisodeArtwork: View {
    @EnvironmentObject private var appState: AppState
    let episode: BaseItem

    var body: some View {
        ZStack {
            PosterImage(url: appState.api.episodeArtworkURL(for: episode, maxWidth: 1280))
            if usesPortraitArtwork {
                LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .center, endPoint: .bottom)
            }
        }
    }

    private var usesPortraitArtwork: Bool {
        guard let ratio = episode.primaryImageAspectRatio else { return false }
        return ratio < 1.25
    }
}

private struct WatchedToggle: View {
    let isPlayed: Bool
    let action: (Bool) -> Void

    var body: some View {
        Button { action(!isPlayed) } label: {
            Image(systemName: isPlayed ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isPlayed ? SolfinDesign.solarGold : .white.opacity(0.9))
                .shadow(color: .black.opacity(0.55), radius: 5)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .help(isPlayed ? "Mark unwatched" : "Mark watched")
        .accessibilityLabel(isPlayed ? "Mark unwatched" : "Mark watched")
    }
}

struct EpisodeCard: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let episode: BaseItem
    @State private var hovering = false
    @State private var playButtonHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .center) {
                EpisodeArtwork(episode: episode)
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                LinearGradient(colors: [.clear, .black.opacity(0.40)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                if episode.userData?.played == true {
                    LinearGradient(colors: [SolfinDesign.solarOrange.opacity(0.14), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                if hovering {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(RadialGradient(colors: [SolfinDesign.solarOrange.opacity(0.34), SolfinDesign.solarRed.opacity(0.18), SolfinDesign.nebulaPurple.opacity(0.22), .clear], center: .center, startRadius: 10, endRadius: 180))
                        .blur(radius: 16)
                        .padding(-14)
                    Button {
                        nowPlaying.play(item: episode, api: appState.api, config: appState.makePlaybackConfig()) {
                            appState.playbackError = $0
                        }
                    } label: {
                        Image(systemName: "play.fill").font(.title3).foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(playButtonHovering ? SolfinDesign.solarOrange.opacity(0.78) : .clear, in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(playButtonHovering ? SolfinDesign.solarGold : SolfinDesign.solarOrange.opacity(0.45), lineWidth: playButtonHovering ? 2 : 1) }
                            .shadow(color: SolfinDesign.solarOrange.opacity(playButtonHovering ? 0.7 : 0.35), radius: playButtonHovering ? 26 : 18, y: 5)
                            .scaleEffect(playButtonHovering ? 1.12 : 1)
                    }
                    .buttonStyle(.plain)
                    .help("Play")
                    .onHover { playButtonHovering = $0 }
                    .animation(.easeOut(duration: 0.16), value: playButtonHovering)
                    .accessibilityLabel("Play \(episode.name)")
                }
                if let pct = episode.userData?.playedPercentage, pct > 0 {
                    GeometryReader { geo in
                        VStack { Spacer(); Rectangle().fill(LinearGradient(colors: [SolfinDesign.solarOrange, SolfinDesign.nebulaPurple], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * min(pct, 100) / 100, height: 4) }
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(hovering ? AnyShapeStyle(LinearGradient(colors: [SolfinDesign.solarOrange, SolfinDesign.solarRed, SolfinDesign.nebulaPurple], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(.white.opacity(0.1)), lineWidth: hovering ? 2 : 1) }
            .shadow(color: .black.opacity(hovering ? 0.22 : 0.1), radius: hovering ? 14 : 5, y: 6)

            HStack(alignment: .firstTextBaseline) {
                Text(episodeTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                if let runtime { Text(runtime).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.58)) }
            }
            if let overview = episode.overview { Text(overview).font(.system(size: 14, weight: .regular)).foregroundStyle(.white.opacity(0.6)).lineLimit(2).lineSpacing(2) }
        }
        // Do not scale the card itself: on macOS the enlarged hit region can
        // overlap adjacent grid cells and make hover state oscillate.
        .contentShape(Rectangle()).onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
    }

    private var runtime: String? {
        guard let ticks = episode.runTimeTicks else { return nil }
        return "\(Int(Ticks.toSeconds(ticks) / 60)) min"
    }
    private var episodeTitle: String { (episode.indexNumber.map { "\($0). " } ?? "") + episode.name }
}
