import SwiftUI
import JellyfinKit

struct SeriesDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var nowPlaying: NowPlaying
    let series: BaseItem

    @State private var seasons: [BaseItem] = []
    @State private var selectedSeasonId: String?
    @State private var episodes: [BaseItem] = []
    @State private var loadError: String?
    @State private var loadingEpisodes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let backdrop = appState.api.backdropImageURL(for: series)
                if backdrop != nil {
                    BackdropHero(url: backdrop, height: 260)
                        .padding(.bottom, -70)
                }
                header
                if seasons.count > 1 { seasonPicker }
                if let err = loadError { Text(err).foregroundStyle(.red) }
                if loadingEpisodes { ProgressView().padding(.top, 8) }
                LazyVStack(spacing: 0) {
                    ForEach(episodes) { ep in
                        EpisodeRow(episode: ep) { play(ep, startOver: $0) }
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(series.name)
        .task { await loadSeasons() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            PosterImage(url: appState.api.primaryImageURL(for: series, maxHeight: 400))
                .frame(width: 160, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 8) {
                Text(series.name).font(.largeTitle.bold())
                HStack(spacing: 10) {
                    if let year = series.productionYear { Text(String(year)) }
                    if let c = series.childCount { Text("\(c) season\(c == 1 ? "" : "s")") }
                }
                .foregroundStyle(.secondary)
                if let overview = series.overview {
                    Text(overview).font(.callout).foregroundStyle(.primary.opacity(0.9)).lineLimit(6)
                }
            }
            Spacer()
        }
    }

    private var seasonPicker: some View {
        Picker("Season", selection: Binding(
            get: { selectedSeasonId ?? seasons.first?.id ?? "" },
            set: { newValue in
                selectedSeasonId = newValue
                Task { await loadEpisodes(seasonId: newValue) }
            }
        )) {
            ForEach(seasons) { season in
                Text(season.name).tag(season.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func play(_ episode: BaseItem, startOver: Bool) {
        appState.playbackError = nil
        nowPlaying.play(item: episode, api: appState.api, config: appState.makePlaybackConfig(),
                        startOver: startOver) { appState.playbackError = $0 }
    }

    private func loadSeasons() async {
        do {
            seasons = try await appState.api.seasons(seriesId: series.id)
            let first = seasons.first?.id
            selectedSeasonId = first
            if let first { await loadEpisodes(seasonId: first) }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadEpisodes(seasonId: String) async {
        loadingEpisodes = true
        defer { loadingEpisodes = false }
        do {
            episodes = try await appState.api.episodes(seriesId: series.id, seasonId: seasonId)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// A single episode row with thumbnail, metadata, resume progress, and play controls.
struct EpisodeRow: View {
    @EnvironmentObject var appState: AppState
    let episode: BaseItem
    let onPlay: (_ startOver: Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                PosterImage(url: appState.api.primaryImageURL(for: episode, maxHeight: 180))
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if let pct = episode.userData?.playedPercentage, pct > 0 {
                    GeometryReader { geo in
                        Rectangle().fill(.tint)
                            .frame(width: geo.size.width * pct / 100, height: 3)
                    }
                    .frame(height: 3)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(episodeTitle).font(.headline)
                    if episode.userData?.played == true {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    }
                    Spacer()
                    if let rt = episode.runTimeTicks {
                        Text("\(Int(Ticks.toSeconds(rt) / 60)) min")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let overview = episode.overview {
                    Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    Button { onPlay(false) } label: {
                        Label(resumeSeconds > 0 ? "Resume" : "Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    if resumeSeconds > 0 {
                        Button { onPlay(true) } label: {
                            Label("Start Over", systemImage: "gobackward")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 12)
    }

    private var resumeSeconds: Double { Ticks.toSeconds(episode.userData?.playbackPositionTicks) }

    private var episodeTitle: String {
        let e = episode.indexNumber.map { "\($0). " } ?? ""
        return "\(e)\(episode.name)"
    }
}
