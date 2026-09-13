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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                seriesHero
                VStack(alignment: .leading, spacing: 32) {
                    if !seasons.isEmpty { seasonsShelf }
                    episodeHeader
                    episodeContent
                }
                .padding(.horizontal, 38).padding(.top, 34).padding(.bottom, 70)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(series.name)
        .task { await loadSeasons() }
    }

    private var seriesHero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let url = appState.api.backdropImageURL(for: series, maxWidth: nil) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                        else { Color.secondary.opacity(0.1) }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else {
                    LinearGradient(colors: [Color.accentColor.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.3), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.black.opacity(0.64), .clear], startPoint: .leading, endPoint: .trailing)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 13) {
                        FeaturedTitleView(item: series)
                        HStack(spacing: 9) {
                            if let year = series.productionYear { heroPill(String(year)) }
                            if let count = series.childCount { heroPill("\(count) season\(count == 1 ? "" : "s")") }
                            if let official = series.officialRating { heroPill(official) }
                            if let rating = series.communityRating {
                                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                            }
                        }
                        if let genres = series.genres, !genres.isEmpty {
                            Text(genres.prefix(4).joined(separator: "  ·  ")).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        }
                        if let overview = series.overview, !overview.isEmpty {
                            Text(overview).font(.callout).lineSpacing(3).foregroundStyle(.white.opacity(0.84))
                                .lineLimit(overviewExpanded ? nil : 3).frame(maxWidth: min(740, proxy.size.width * 0.58), alignment: .leading)
                            if overview.count > 420 {
                                Button(overviewExpanded ? "Show Less" : "More") { withAnimation { overviewExpanded.toggle() } }
                                    .buttonStyle(.plain).font(.callout.weight(.semibold)).foregroundStyle(.white)
                            }
                        }
                        if let next = nextEpisode {
                            Button { play(next, startOver: false) } label: {
                                Label(playLabel(next), systemImage: "play.fill").padding(.horizontal, 8).padding(.vertical, 3)
                            }.buttonStyle(.borderedProminent).controlSize(.large).tint(.white).foregroundStyle(.black)
                        }
                    }
                    Spacer()
                }.padding(.horizontal, 48).padding(.bottom, 42)
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
        .containerRelativeFrame(.vertical, alignment: .top) { available, _ in
            max(700, available - 44)
        }
    }

    private var seasonsShelf: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Seasons").font(.title2.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(seasons) { season in
                        Button {
                            guard selectedSeasonId != season.id else { return }
                            selectedSeasonId = season.id
                            Task { await loadEpisodes(seasonId: season.id) }
                        } label: {
                            SeasonCard(season: season, selected: season.id == selectedSeasonId)
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 6).padding(.horizontal, 2)
            }
        }
    }

    private var episodeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSeason?.name ?? "Episodes").font(.title2.weight(.semibold))
                if !episodes.isEmpty { Text("\(episodes.count) episodes").font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }

    @ViewBuilder private var episodeContent: some View {
        if loadingEpisodes && episodes.isEmpty { episodeSkeleton }
        else if let loadError, episodes.isEmpty {
            EmptyContentView(title: "Episodes unavailable", message: loadError, systemImage: "wifi.exclamationmark") {
                if let selectedSeasonId { Task { await loadEpisodes(seasonId: selectedSeasonId) } }
            }
        } else if episodes.isEmpty { EmptyContentView(title: "No episodes", message: "This season does not contain any episodes.") }
        else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 430), spacing: 18)], alignment: .leading, spacing: 22) {
                ForEach(episodes) { episode in
                    NavigationLink(value: episode) { EpisodeCard(episode: episode) }.buttonStyle(.plain)
                        .contextMenu {
                            Button(resumeSeconds(episode) > 0 ? "Resume" : "Play") { play(episode, startOver: false) }
                            if resumeSeconds(episode) > 0 { Button("Start Over") { play(episode, startOver: true) } }
                        }
                }
            }.opacity(loadingEpisodes ? 0.55 : 1)
        }
    }

    private var episodeSkeleton: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 430), spacing: 18)], spacing: 22) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 13).fill(.secondary.opacity(0.12)).aspectRatio(16/9, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.12)).frame(width: 220, height: 17)
                    RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.08)).frame(height: 12)
                }
            }
        }.redacted(reason: .placeholder)
    }

    private var selectedSeason: BaseItem? { seasons.first { $0.id == selectedSeasonId } }
    private var nextEpisode: BaseItem? { episodes.first { $0.userData?.played != true } }
    private func heroPill(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9).padding(.vertical, 5).background(.black.opacity(0.3), in: Capsule())
    }
    private func resumeSeconds(_ episode: BaseItem) -> Double { Ticks.toSeconds(episode.userData?.playbackPositionTicks) }
    private func playLabel(_ episode: BaseItem) -> String { resumeSeconds(episode) > 0 ? "Resume Episode" : "Play Episode" }
    private func play(_ episode: BaseItem, startOver: Bool) {
        appState.playbackError = nil
        nowPlaying.play(item: episode, api: appState.api, config: appState.makePlaybackConfig(), startOver: startOver) { appState.playbackError = $0 }
    }
    private func loadSeasons() async {
        loadError = nil
        do {
            seasons = try await appState.api.seasons(seriesId: series.id)
            if let first = seasons.first { selectedSeasonId = first.id; await loadEpisodes(seasonId: first.id) }
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

private struct FeaturedTitleView: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem
    var body: some View {
        if let url = appState.api.logoImageURL(for: item, maxWidth: 760) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fit) }
                else { fallback }
            }.frame(width: 500, height: 150, alignment: .leading)
        } else { fallback }
    }
    private var fallback: some View {
        Text(item.name).font(.system(size: 48, weight: .bold, design: .rounded)).tracking(-1.2)
            .foregroundStyle(.white).lineLimit(2).frame(maxWidth: 650, alignment: .leading)
    }
}

private struct SeasonCard: View {
    @EnvironmentObject private var appState: AppState
    let season: BaseItem
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImage(url: appState.api.primaryImageURL(for: season, maxHeight: 420))
                .frame(width: 170, height: 255).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .white.opacity(0.1), lineWidth: selected ? 3 : 1) }
            Text(season.name).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
            if let count = season.childCount { Text("\(count) episodes").font(.caption).foregroundStyle(.secondary) }
        }.frame(width: 170, alignment: .leading)
    }
}

struct EpisodeCard: View {
    @EnvironmentObject private var appState: AppState
    let episode: BaseItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                PosterImage(url: appState.api.primaryImageURL(for: episode, maxHeight: 320))
                    .aspectRatio(16/9, contentMode: .fill).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                if hovering {
                    Image(systemName: "play.fill").font(.title3).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(.black.opacity(0.55), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let pct = episode.userData?.playedPercentage, pct > 0 {
                    GeometryReader { geo in
                        VStack { Spacer(); Rectangle().fill(.tint).frame(width: geo.size.width * min(pct, 100) / 100, height: 4) }
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(hovering ? Color.accentColor : .white.opacity(0.1), lineWidth: hovering ? 2 : 1) }
            .shadow(color: .black.opacity(hovering ? 0.22 : 0.1), radius: hovering ? 14 : 5, y: 6)
            .scaleEffect(hovering ? 1.015 : 1)

            HStack(alignment: .firstTextBaseline) {
                Text(episodeTitle).font(.headline).lineLimit(1)
                Spacer()
                if let runtime { Text(runtime).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            if let overview = episode.overview { Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(2).lineSpacing(2) }
        }
        .contentShape(Rectangle()).onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
    }

    private var runtime: String? {
        guard let ticks = episode.runTimeTicks else { return nil }
        return "\(Int(Ticks.toSeconds(ticks) / 60)) min"
    }
    private var episodeTitle: String { (episode.indexNumber.map { "\($0). " } ?? "") + episode.name }
}
