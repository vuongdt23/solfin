import SwiftUI
import JellyfinKit

struct SeriesDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let series: BaseItem
    /// Space reserved for the shell rail. Artwork remains edge-to-edge, while
    /// readable series copy starts beside the rail instead of beneath it.
    var sidebarLeadingInset: CGFloat = 64

    @State private var seasons: [BaseItem] = []
    @State private var selectedSeasonId: String?
    @State private var episodes: [BaseItem] = []
    @State private var loadError: String?
    @State private var loadingEpisodes = true
    @State private var episodeLoadID = UUID()
    @State private var overviewExpanded = false
    @State private var heroPlayHovering = false

    var body: some View {
        GeometryReader { proxy in
            let layout = DetailLayout(viewport: proxy.size, railWidth: sidebarLeadingInset)
            ScrollView {
                seriesHero(layout: layout)
            }
        }
        .background(SolfinDesign.solarBackground)
        .navigationTitle(series.name)
        .task { await loadSeasons() }
    }

    private func seriesHero(layout: DetailLayout) -> some View {
        // Content owns scroll height. Tall windows reveal more art; short windows
        // prioritize browsing without a fixed-height hero pushing seasons away.
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            heroCopy(layout: layout)
                .padding(.top, layout.topSpacing)
                .frame(minHeight: layout.seriesHeroHeight, alignment: .bottomLeading)
            if !seasons.isEmpty { seasonsShelf(layout: layout) }
            VStack(alignment: .leading, spacing: 20) {
                episodeHeader
                episodeContent(layout: layout)
            }
        }
        .frame(width: layout.collectionWidth, alignment: .leading)
        .padding(.leading, layout.leadingInset)
        .padding(.trailing, layout.trailingInset)
        .padding(.bottom, 70)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: layout.viewport.height, alignment: .topLeading)
        .background(alignment: .topLeading) {
            // Preserve the oversized artwork canvas independently of the grid.
            seriesBackdrop
                .frame(width: layout.viewport.width, height: layout.artworkHeight, alignment: .top)
                .allowsHitTesting(false)
        }
    }

    private var seriesBackdrop: some View {
        ZStack {
            Color.black
            if let url = appState.api.backdropImageURL(for: series, maxWidth: nil) {
                ZStack {
                    CachedImage(url: url, contentMode: .fill)
                        .scaleEffect(1.12)
                        .blur(radius: 28)
                        .opacity(0.72)
                        .overlay(Color.black.opacity(0.28))
                    CachedImage(url: url, contentMode: .fit)
                }
                .clipped()
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
        // Preserve the oversized, overflowing artwork treatment on wide displays.
        // The readable content is inset separately, so the rail never obscures it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func heroCopy(layout: DetailLayout) -> some View {
        let copyWidth = layout.copyWidth
        return VStack(alignment: .leading, spacing: 15) {
            SolarMediaLogo(item: series,
                           maxWidth: layout.logoWidth,
                           height: layout.logoHeight,
                           fallbackSize: layout.titleSize)
            SolarSeriesMetadata(series: series, seasonCount: seasonCount, wraps: true)
            if let genres = series.genres { SolarGenreRow(genres: genres) }
            if let overview = series.overview, !overview.isEmpty {
                SolarHeroOverview(text: overview,
                                  maxWidth: copyWidth,
                                  lineLimit: overviewExpanded ? nil : 3)
                if overview.count > 140 {
                    Button(overviewExpanded ? "Show Less" : "More") { withAnimation { overviewExpanded.toggle() } }
                        .buttonStyle(.plain)
                        .font(DetailTypography.font(DetailTypography.supporting, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            if let episode = defaultPlaybackEpisode {
                Button { play(episode, startOver: false, queue: allQueuedEpisodes,
                              queueIndex: allQueuedEpisodes.firstIndex(where: { $0.id == episode.id })) } label: {
                    Label(playLabel(for: episode), systemImage: "play.fill")
                        .font(DetailTypography.font(DetailTypography.control, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                }
                .buttonStyle(SolarPillButtonStyle(hovering: heroPlayHovering))
                .onHover { heroPlayHovering = $0 }
                .animation(.easeOut(duration: 0.16), value: heroPlayHovering)
                .controlSize(.large)
                .disabled(loadingEpisodes)
                .help(episode.name)
            }
        }
        .frame(maxWidth: copyWidth, alignment: .leading)
    }


    private func seasonsShelf(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Seasons").font(DetailTypography.font(DetailTypography.sectionTitle, weight: .bold))
                    if let season = selectedSeason, let summary = seasonSummary(season) {
                        Text(summary)
                            .font(DetailTypography.font(DetailTypography.supporting))
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
                                   width: layout.seasonCardWidth,
                                   onSelect: {
                                       guard selectedSeasonId != season.id else { return }
                                       selectedSeasonId = season.id
                                       episodes = []
                                       loadingEpisodes = true
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
                Text(selectedSeason.map { "\($0.name) · Episodes" } ?? "Episodes")
                    .font(DetailTypography.font(DetailTypography.sectionTitle, weight: .bold))
                if !episodes.isEmpty {
                    Text(episodeHeaderSummary).font(DetailTypography.font(DetailTypography.supporting)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if loadingEpisodes && !episodes.isEmpty {
                ProgressView().controlSize(.small).tint(SolfinDesign.solarOrange)
            }
        }
    }

    private func episodeGridColumns(_ layout: DetailLayout) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 20, alignment: .top),
              count: layout.episodeColumns)
    }

    @ViewBuilder private func episodeContent(layout: DetailLayout) -> some View {
        if loadingEpisodes && episodes.isEmpty { episodeSkeleton(layout: layout) }
        else if let loadError, episodes.isEmpty {
            EmptyContentView(title: "Episodes unavailable", message: loadError, systemImage: "wifi.exclamationmark") {
                Task {
                    if let selectedSeasonId { await loadEpisodes(seasonId: selectedSeasonId) }
                    else { await loadSeasons() }
                }
            }
        } else if episodes.isEmpty {
            EmptyContentView(title: "No episodes", message: "This season does not contain any episodes.")
        } else {
            LazyVGrid(columns: episodeGridColumns(layout),
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

    private func episodeSkeleton(layout: DetailLayout) -> some View {
        LazyVGrid(columns: episodeGridColumns(layout), spacing: 22) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 13).fill(.secondary.opacity(0.12)).aspectRatio(16/9, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.12)).frame(maxWidth: 220, minHeight: 17)
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

    private func resumeSeconds(_ episode: BaseItem) -> Double { Ticks.toSeconds(episode.userData?.playbackPositionTicks) }
    private func playLabel(for episode: BaseItem) -> String {
        let action = resumeSeconds(episode) > 0 ? "Resume" : "Play"
        let code = [episode.parentIndexNumber.map { "S\($0)" },
                    episode.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined()
        return code.isEmpty ? action : "\(action) · \(code)"
    }
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
        loadingEpisodes = false
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

private struct SeasonCard: View {
    @EnvironmentObject private var appState: AppState
    let season: BaseItem
    let selected: Bool
    let width: CGFloat
    let onSelect: () -> Void
    let onPlay: () -> Void
    @State private var hovering = false
    @State private var playHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                PosterImage(url: appState.api.primaryImageURL(for: season, maxHeight: 420))
                    .frame(width: width, height: width * 1.5).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .frame(width: 58, height: 58)
                    }
                    .buttonStyle(SolarRoundButtonStyle(hovering: playHovering, idleFill: .black.opacity(0.28)))
                    .help("Play season")
                    .accessibilityLabel("Play \(season.name)")
                    .onHover { playHovering = $0 }
                    .animation(.easeOut(duration: 0.16), value: playHovering)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .animation(.easeOut(duration: 0.16), value: hovering)
            }
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(selected ? 0.28 : 0.1), lineWidth: selected ? 2 : 1) }
            .cardHoverEffect(isActive: hovering, lift: 6, scale: 1.035)
            // Keep the artwork container from expanding to the height proposed by
            // the surrounding hero stack. Without this constraint the overlay can
            // stretch into a tall, empty card while the poster remains centered.
            .frame(width: width, height: width * 1.5)
            Text(season.name).font(DetailTypography.font(DetailTypography.cardTitle, weight: selected ? .semibold : .regular)).foregroundStyle(.white).lineLimit(1)
            if let count = season.childCount { Text("\(count) episodes").font(DetailTypography.font(DetailTypography.supporting)).foregroundStyle(.white.opacity(0.78)) }
        }
        .frame(width: width, alignment: .leading)
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
                .font(DetailTypography.font(DetailTypography.cardTitle, weight: .semibold))
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
            GeometryReader { proxy in
                ZStack(alignment: .center) {
                    EpisodeArtwork(episode: episode)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                LinearGradient(colors: [.clear, .black.opacity(0.40)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                if episode.userData?.played == true {
                    LinearGradient(colors: [SolfinDesign.solarOrange.opacity(0.14), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                if hovering {
                    Button {
                        nowPlaying.play(item: episode, api: appState.api, config: appState.makePlaybackConfig()) {
                            appState.playbackError = $0
                        }
                    } label: {
                        Image(systemName: "play.fill").font(.title3)
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(SolarRoundButtonStyle(hovering: playButtonHovering, idleFill: .clear))
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
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipped()
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.1)) }
            .cardHoverEffect(isActive: hovering, lift: 6, scale: 1.035)
            .shadow(color: .black.opacity(hovering ? 0.22 : 0.1), radius: hovering ? 14 : 5, y: 6)

            HStack(alignment: .firstTextBaseline) {
                Text(episodeTitle).font(DetailTypography.font(DetailTypography.cardTitle, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                if let runtime { Text(runtime).font(DetailTypography.font(DetailTypography.supporting, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.72)) }
            }
            if let overview = episode.overview { Text(overview).font(DetailTypography.font(DetailTypography.supporting, weight: .regular)).foregroundStyle(.white.opacity(0.82)).lineLimit(2).lineSpacing(3) }
        }
        // Do not scale the card itself: on macOS the enlarged hit region can
        // overlap adjacent grid cells and make hover state oscillate.
        .contentShape(Rectangle()).onHover { hovering = $0 }
    }

    private var runtime: String? {
        guard let ticks = episode.runTimeTicks else { return nil }
        return "\(Int(Ticks.toSeconds(ticks) / 60)) min"
    }
    private var episodeTitle: String { (episode.indexNumber.map { "\($0). " } ?? "") + episode.name }
}
