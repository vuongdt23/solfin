import SwiftUI
import JellyfinKit

/// One artwork-led detail surface for every playable video.
struct ItemDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let itemId: String

    @State private var item: BaseItem?
    @State private var previousEpisode: BaseItem?
    @State private var nextEpisode: BaseItem?
    @State private var loadError: String?
    @State private var overviewExpanded = false
    @State private var selectedAudioTrack: Int?
    @State private var selectedVideoTrack: Int?
    @State private var selectedSubtitleTrack: Int? = -1

    var body: some View {
        ScrollView {
            if let item { playableDetail(item) }
            else if let loadError {
                EmptyContentView(title: "Details unavailable", message: loadError,
                                 systemImage: "wifi.exclamationmark") { Task { await load() } }
                    .padding(SolfinDesign.pagePadding)
            } else { detailSkeleton }
        }
        .background(SolfinDesign.solarBackground)
        .navigationTitle(item?.name ?? "Details")
        .task(id: itemId) { await load() }
    }

    private func playableDetail(_ item: BaseItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            immersiveDetail(item)
            if item.type == "Episode", previousEpisode != nil || nextEpisode != nil {
                VStack(alignment: .leading, spacing: 15) {
                    Text("More from \(item.seriesName ?? "this series")").font(.title2.weight(.semibold))
                    adjacentEpisodeSection
                }
                .padding(.horizontal, 42).padding(.vertical, 34)
            }
        }
    }

    private func immersiveDetail(_ item: BaseItem) -> some View {
        GeometryReader { proxy in
            ZStack {
                backdrop(item, size: proxy.size)
                solarAura
                cinematicScrim

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 96)
                    VStack(alignment: .leading, spacing: 20) {
                        identity(item, availableWidth: proxy.size.width)
                        overview(item)
                        if let genres = item.genres, !genres.isEmpty {
                            Text(genres.prefix(5).joined(separator: "  ·  "))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                        playbackError
                        trackPanel(item)
                    }
                    .frame(maxWidth: 1280, alignment: .leading)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 50)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .containerRelativeFrame(.vertical, alignment: .top) { available, _ in max(720, available - 8) }
    }

    @ViewBuilder private func backdrop(_ item: BaseItem, size: CGSize) -> some View {
        if let url = backdropURL(item) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                else { Color.secondary.opacity(0.1) }
            }
            .frame(width: size.width, height: size.height).clipped()
        } else if let poster = appState.api.playablePosterURL(for: item, maxHeight: nil) {
            ZStack {
                AsyncImage(url: poster) { phase in
                    if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                    else { Color.secondary.opacity(0.1) }
                }
                .frame(width: size.width, height: size.height).clipped().blur(radius: 24).scaleEffect(1.08)
                AsyncImage(url: poster) { phase in
                    if let image = phase.image { image.resizable().aspectRatio(contentMode: .fit) }
                }.padding(.vertical, 40)
            }
        } else {
            LinearGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.38), SolfinDesign.spaceBlack],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var cinematicScrim: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.08), .clear, SolfinDesign.spaceBlack.opacity(0.62)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.08)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }

    private var solarAura: some View {
        ZStack {
            RadialGradient(colors: [SolfinDesign.solarGold.opacity(0.62), SolfinDesign.solarOrange.opacity(0.28), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 760)
            RadialGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.32), .clear],
                           center: .bottomLeading, startRadius: 40, endRadius: 780)
        }
        .blendMode(.screen)
    }

    private func identity(_ item: BaseItem, availableWidth: CGFloat) -> some View {
        let logoWidth = min(1120, max(620, availableWidth * 0.62))
        let logoHeight = min(360, max(220, availableWidth * 0.21))
        let titleSize = min(88, max(58, availableWidth * 0.052))
        return VStack(alignment: .leading, spacing: 14) {
            if let context = contextTitle(item) {
                Text(context.uppercased())
                    .font(.caption.weight(.bold)).tracking(1.6)
                    .foregroundStyle(.white.opacity(0.68))
            }
            if let logoURL = appState.api.logoImageURL(for: item, maxWidth: nil) {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image { image.resizable().aspectRatio(contentMode: .fit) }
                    else { titleFallback(item, size: titleSize) }
                }
                .frame(width: logoWidth, height: logoHeight, alignment: .leading)
            } else { titleFallback(item, size: titleSize) }
            heroMetadata(item)
            actions(item)
        }
        .shadow(color: .black.opacity(0.48), radius: 12, y: 3)
    }

    private func titleFallback(_ item: BaseItem, size: CGFloat) -> some View {
        Text(item.name)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .tracking(-1.6).foregroundStyle(.white)
            .multilineTextAlignment(.leading).lineLimit(2)
            .frame(maxWidth: 820, alignment: .leading)
    }

    private func heroMetadata(_ item: BaseItem) -> some View {
        HStack(spacing: 10) {
            if item.type == "Episode" { metadataText(episodeCode(item)) }
            if let year = item.productionYear { metadataText(String(year)) }
            if let runtime = runtime(item) { metadataText(runtime) }
            if let rating = item.officialRating {
                Text(rating).font(.caption.weight(.semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 4))
            }
            if let score = item.communityRating {
                Label(String(format: "%.1f", score), systemImage: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
            }
            if item.userData?.played == true {
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
            }
        }
    }

    private func metadataText(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
    }

    private func actions(_ item: BaseItem) -> some View {
        HStack(spacing: 10) {
            Button { play(item) } label: {
                Label(playLabel(item), systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 20).frame(height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(.white, in: Capsule())

            if resumeSeconds(item) > 0 {
                Button { play(item, startOver: true) } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16).frame(height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(.white.opacity(0.14), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.16)) }
            }
        }
    }

    @ViewBuilder private func overview(_ item: BaseItem) -> some View {
        if let overview = item.overview, !overview.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(overview)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .lineLimit(overviewExpanded ? nil : 6)
                    .frame(maxWidth: 1040, alignment: .leading)
                if overview.count > 620 {
                    Button(overviewExpanded ? "Show Less" : "More") { withAnimation { overviewExpanded.toggle() } }
                        .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(.white)
                }
            }.frame(maxWidth: 1040, alignment: .leading)
        }
    }

    @ViewBuilder private func trackPanel(_ item: BaseItem) -> some View {
        let audio = tracks(item, type: "Audio")
        let video = tracks(item, type: "Video")
        let subtitles = tracks(item, type: "Subtitle")
        if !audio.isEmpty || !video.isEmpty || !subtitles.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("PLAYBACK OPTIONS")
                    .font(.caption2.weight(.bold)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                Divider().overlay(.white.opacity(0.1))
                if !video.isEmpty {
                    trackRow(title: "Video", icon: "film", selection: $selectedVideoTrack, tracks: video, includesOff: false)
                    Divider().overlay(.white.opacity(0.08)).padding(.leading, 52)
                }
                if !audio.isEmpty {
                    trackRow(title: "Audio", icon: "waveform", selection: $selectedAudioTrack, tracks: audio, includesOff: false)
                    Divider().overlay(.white.opacity(0.08)).padding(.leading, 52)
                }
                trackRow(title: "Subtitles", icon: "captions.bubble", selection: $selectedSubtitleTrack,
                         tracks: subtitles, includesOff: true)
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14)) }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .frame(maxWidth: 920)
        }
    }

    private func trackRow(title: String, icon: String, selection: Binding<Int?>,
                          tracks: [(id: Int, stream: MediaStream)], includesOff: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 24).foregroundStyle(.white.opacity(0.72))
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.84))
                .frame(width: 76, alignment: .leading)
            Spacer(minLength: 12)
            Menu {
                if includesOff { Button("Off") { selection.wrappedValue = -1 } }
                ForEach(tracks, id: \.id) { track in
                    Button { selection.wrappedValue = track.id } label: {
                        if selection.wrappedValue == track.id { Label(trackLabel(track), systemImage: "checkmark") }
                        else { Text(trackLabel(track)) }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(selectedTrackLabel(selection.wrappedValue, tracks: tracks, includesOff: includesOff))
                        .font(.callout).lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12).frame(height: 34)
                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.13)) }
            }.menuStyle(.borderlessButton).frame(maxWidth: 560, alignment: .trailing)
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var adjacentEpisodeSection: some View {
        HStack(alignment: .top, spacing: 18) {
            if let previousEpisode { adjacentCard(previousEpisode, label: "Previous Episode") }
            if let nextEpisode { adjacentCard(nextEpisode, label: "Next Episode") }
        }
    }
    private func adjacentCard(_ episode: BaseItem, label: String) -> some View {
        NavigationLink(value: episode) {
            HStack(spacing: 14) {
                PosterImage(url: appState.api.primaryImageURL(for: episode, maxHeight: 180))
                    .frame(width: 170, height: 96).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(label.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                    Text(episode.name).font(.headline).lineLimit(2)
                    Text(episodeCode(episode)).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(12).frame(maxWidth: 440, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var playbackError: some View {
        if let error = appState.playbackError {
            Label(error, systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.red).padding(12)
                .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var detailSkeleton: some View {
        VStack(spacing: 26) {
            Spacer()
            RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.12)).frame(width: 520, height: 110)
            RoundedRectangle(cornerRadius: 12).fill(.secondary.opacity(0.08)).frame(maxWidth: 900, minHeight: 150)
            Spacer()
        }.frame(maxWidth: .infinity, minHeight: 720).redacted(reason: .placeholder)
    }

    private func tracks(_ item: BaseItem, type: String) -> [(id: Int, stream: MediaStream)] {
        (item.mediaSources?.first?.mediaStreams ?? []).filter { $0.type == type }
            .enumerated().map { ($0.element.index ?? $0.offset + 1, $0.element) }
    }
    private func trackLabel(_ track: (id: Int, stream: MediaStream)) -> String {
        track.stream.displayTitle ?? track.stream.language ?? "Track \(track.id)"
    }
    private func selectedTrackLabel(_ id: Int?, tracks: [(id: Int, stream: MediaStream)], includesOff: Bool) -> String {
        if includesOff && (id == nil || id == -1) { return "Off" }
        guard let id, let track = tracks.first(where: { $0.id == id }) else { return "Default" }
        return trackLabel(track)
    }
    private func backdropURL(_ item: BaseItem) -> URL? {
        item.type == "Episode" ? appState.api.episodeBackdropURL(for: item, maxWidth: nil)
                               : appState.api.backdropImageURL(for: item, maxWidth: nil)
    }
    private func contextTitle(_ item: BaseItem) -> String? { item.type == "Episode" ? item.seriesName : item.type }
    private func episodeCode(_ item: BaseItem) -> String {
        (item.parentIndexNumber.map { "S\($0)" } ?? "") + (item.indexNumber.map { "E\($0)" } ?? "")
    }
    private func runtime(_ item: BaseItem) -> String? {
        guard let ticks = item.runTimeTicks else { return nil }; let minutes = Int(Ticks.toSeconds(ticks) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    private func resumeSeconds(_ item: BaseItem) -> Double { Ticks.toSeconds(item.userData?.playbackPositionTicks) }
    private func playLabel(_ item: BaseItem) -> String {
        let seconds = resumeSeconds(item); return seconds > 0 ? "Resume · \(Int(seconds / 60)) min" : "Play"
    }
    private func play(_ item: BaseItem, startOver: Bool = false) {
        appState.playbackError = nil
        nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig(),
                        startOver: startOver, audioTrack: selectedAudioTrack,
                        videoTrack: selectedVideoTrack, subtitleTrack: selectedSubtitleTrack) {
            appState.playbackError = $0
        }
    }
    private func load() async {
        loadError = nil; previousEpisode = nil; nextEpisode = nil
        do {
            let loaded = try await appState.api.item(id: itemId); item = loaded
            configureTrackDefaults(for: loaded)
            if loaded.type == "Episode" {
                let adjacent = try? await appState.api.adjacentEpisodes(to: loaded)
                previousEpisode = adjacent?.previous; nextEpisode = adjacent?.next
            }
        } catch { loadError = error.localizedDescription }
    }
    private func configureTrackDefaults(for item: BaseItem) {
        let audio = tracks(item, type: "Audio"), video = tracks(item, type: "Video"), subtitles = tracks(item, type: "Subtitle")
        let source = item.mediaSources?.first
        selectedAudioTrack = source?.defaultAudioStreamIndex
            ?? audio.first(where: { $0.stream.isDefault == true })?.id
            ?? audio.first?.id
        selectedVideoTrack = video.first(where: { $0.stream.isDefault == true })?.id ?? video.first?.id
        selectedSubtitleTrack = source?.defaultSubtitleStreamIndex
            ?? subtitles.first(where: { $0.stream.isDefault == true })?.id
            ?? -1
    }
}
