import SwiftUI
import UniformTypeIdentifiers
import JellyfinKit
import PlaybackEngine

/// One artwork-led detail surface for every playable video.
private struct EpisodeDetailView: View {
    let background: (CGSize) -> AnyView
    let still: (CGSize) -> AnyView
    let content: (CGFloat) -> AnyView
    let moreContent: AnyView?
    let aura: () -> AnyView
    let scrim: () -> AnyView

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                background(proxy.size)
                aura()
                still(proxy.size)
                scrim()

                // Keep the episode information, still, and related episodes in one
                // centered poster canvas. The related block is part of the hero,
                // rather than a second section that pushes the user into a scroll.
                content(proxy.size.width)
                    .frame(maxWidth: 1480, maxHeight: .infinity, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 42)

                if let moreContent {
                    VStack {
                        Spacer()
                        moreContent
                    }
                    .frame(maxWidth: 1480, maxHeight: .infinity, alignment: .bottomLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 42)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height,
                   alignment: .top)
        }
        .containerRelativeFrame(.vertical, alignment: .top) { available, _ in max(760, available - 8) }
    }
}

private struct MovieDetailView: View {
    let background: (CGSize) -> AnyView
    let content: (CGFloat) -> AnyView
    let aura: () -> AnyView
    let scrim: () -> AnyView

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                background(proxy.size)
                aura()
                scrim()
                content(proxy.size.width)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height,
                   alignment: .bottomLeading)
        }
        .containerRelativeFrame(.vertical, alignment: .top) { available, _ in max(720, available - 8) }
    }
}

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
    @State private var pendingPlayAction: PlayAction?
    @State private var showSubtitleImporter = false
    @State private var showMediaInfo = false
    @State private var uploadMessage: String?
    @State private var primaryPlayButtonHovering = false
    @State private var startOverButtonHovering = false

    private enum PlayAction: Equatable {
        case primary
        case startOver
    }

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
        .task(id: item?.id) {
            guard let item else { return }
            await LogoOverlayCache.shared.prefetch(for: item, api: appState.api)
        }
        .onChange(of: nowPlaying.isLaunching) { _, isLaunching in
            if !isLaunching { pendingPlayAction = nil }
        }
    }

    private func playableDetail(_ item: BaseItem) -> some View {
        immersiveDetail(item)
    }

    @ViewBuilder private func immersiveDetail(_ item: BaseItem) -> some View {
        if item.type == "Episode" {
            EpisodeDetailView(
                background: { AnyView(self.episodeBackdrop(item, size: $0)) },
                still: { AnyView(self.episodeStill(item, size: $0)) },
                content: { width in AnyView(detailCopy(item, availableWidth: width, episodeStyle: true)) },
                moreContent: previousEpisode != nil || nextEpisode != nil ? AnyView(
                    VStack(alignment: .leading, spacing: 15) {
                        Text("More from \(item.seriesName ?? "this series")")
                            .font(.title2.weight(.semibold))
                        adjacentEpisodeSection
                    }
                    .padding(.horizontal, 42)
                    .padding(.top, 0)
                    .padding(.bottom, 34)
                ) : nil,
                aura: { AnyView(solarAura) },
                scrim: { AnyView(cinematicScrim) }
            )
        } else {
            MovieDetailView(
                background: { AnyView(self.backdrop(item, size: $0)) },
                content: { width in AnyView(detailCopy(item, availableWidth: width)) },
                aura: { AnyView(solarAura) },
                scrim: { AnyView(cinematicScrim) }
            )
        }
    }

    private func detailCopy(_ item: BaseItem, availableWidth: CGFloat = 1280,
                            episodeStyle: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            identity(item, availableWidth: availableWidth)
            overview(item)
            if let genres = item.genres, !genres.isEmpty {
                Text(genres.prefix(5).joined(separator: "  ·  "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
            }
            playbackError
            trackPanel(item, episodeStyle: episodeStyle)
            detailActions(item)
        }
        .frame(maxWidth: 1280, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 42)
        .padding(.top, episodeStyle ? 12 : 42)
        .padding(.bottom, episodeStyle ? 12 : 32)
    }

    @ViewBuilder private func backdrop(_ item: BaseItem, size: CGSize) -> some View {
        if let url = backdropURL(item) {
            CachedImage(url: url)
                .frame(width: size.width, height: size.height).clipped()
        } else if let poster = appState.api.playablePosterURL(for: item, maxHeight: nil) {
            ZStack {
                CachedImage(url: poster)
                    .frame(width: size.width, height: size.height).clipped().blur(radius: 24).scaleEffect(1.08)
                CachedImage(url: poster, contentMode: .fit).padding(.vertical, 40)
            }
        } else {
            LinearGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.38), SolfinDesign.spaceBlack],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func episodeBackdrop(_ item: BaseItem, size: CGSize) -> some View {
        ZStack {
            if let hero = appState.api.seriesHeroBackdropURL(for: item, maxWidth: nil) {
                CachedImage(url: hero, contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 28)
                    .opacity(0.86)
            } else if let poster = appState.api.playablePosterURL(for: item, maxHeight: nil) {
                CachedImage(url: poster, contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 28)
                    .opacity(0.86)
            } else {
                Color.black
            }
        }
    }

    private func episodeStill(_ item: BaseItem, size: CGSize) -> some View {
        let stillURL = appState.api.episodeArtworkURL(for: item, maxWidth: 1600)
        let width = min(980, max(520, size.width * 0.48))
        let aspect = max(1.25, min(2.0, item.primaryImageAspectRatio ?? (16.0 / 9.0)))
        let height = min(size.height * 0.58, width / aspect)
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        return HStack {
            Spacer()
            ZStack {
                // A soft duplicate gives the artwork a diffused border instead of
                // a hard rectangular cutout against the blurred backdrop.
                CachedImage(url: stillURL)
                    .frame(width: width + 24, height: height + 24)
                    .blur(radius: 18)
                    .opacity(0.28)
                    .mask(shape.fill(.white))

                CachedImage(url: stillURL)
                    .frame(width: width, height: height)
                    // Blur the alpha boundary itself so no crisp rectangular
                    // edge remains around the still.
                    .mask {
                        shape
                            .fill(.white)
                            .blur(radius: 18)
                    }
                    .opacity(0.94)
            }
            .padding(.trailing, max(32, size.width * 0.06))
        }
        // Match the still's vertical center to the title / controls block.
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var cinematicScrim: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.18)],
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
        let isEpisode = item.type == "Episode"
        let logoWidth = min(1120, max(620, availableWidth * 0.62))
        let logoHeight = min(360, max(220, availableWidth * 0.21))
        let titleSize = min(88, max(58, availableWidth * 0.052))
        let seriesLogo = isEpisode ? episodeSeriesLogoURL(item) : nil
        return SolarHeroIdentity(
            item: item,
            context: isEpisode ? nil : contextTitle(item),
            episodeCode: isEpisode ? episodeCode(item) : nil,
            runtime: runtime(item),
            overview: nil,
            logoURL: seriesLogo,
            logoWidth: isEpisode ? min(280, max(180, availableWidth * 0.20)) : logoWidth,
            logoHeight: isEpisode ? 54 : logoHeight,
            fallbackSize: titleSize,
            lookupDefaultLogo: !isEpisode
        ) {
            actions(item)
        }
    }

    private func actions(_ item: BaseItem) -> some View {
        let isWaitingForLaunch = pendingPlayAction != nil
        return HStack(spacing: 10) {
            playButton(item, action: .primary, title: playLabel(item), systemImage: "play.fill",
                       isPrimary: true, isBusy: pendingPlayAction == .primary && isWaitingForLaunch,
                       hovering: primaryPlayButtonHovering)
                .onHover { primaryPlayButtonHovering = $0 }

            if resumeSeconds(item) > 0 {
                playButton(item, action: .startOver, title: "Start Over", systemImage: "arrow.counterclockwise",
                           isPrimary: false, isBusy: pendingPlayAction == .startOver && isWaitingForLaunch,
                           hovering: startOverButtonHovering)
                    .onHover { startOverButtonHovering = $0 }
            }
        }
        .disabled(isWaitingForLaunch)
        .animation(.easeOut(duration: 0.16), value: pendingPlayAction)
    }

    private func playButton(_ item: BaseItem, action: PlayAction, title: String,
                            systemImage: String, isPrimary: Bool, isBusy: Bool,
                            hovering: Bool) -> some View {
        Button {
            guard pendingPlayAction == nil, !nowPlaying.isLaunching else { return }
            pendingPlayAction = action
            play(item, startOver: action == .startOver)
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.82)
                        .tint(isPrimary ? .black : .white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(isBusy ? "Starting…" : title)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, isPrimary ? 20 : 16)
            .frame(height: 42)
            .contentShape(Capsule())
        }
        .buttonStyle(SolarPillButtonStyle(hovering: hovering))
        .opacity(pendingPlayAction == nil || isBusy ? 1 : 0.62)
    }

    @ViewBuilder private func overview(_ item: BaseItem) -> some View {
        if let overview = item.overview, !overview.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(overview)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .lineLimit(overviewExpanded ? nil : 3)
                    .frame(maxWidth: 1040, alignment: .leading)
                if overview.count > 620 {
                    Button(overviewExpanded ? "Show Less" : "More") { withAnimation { overviewExpanded.toggle() } }
                        .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(.white)
                }
            }.frame(maxWidth: 1040, alignment: .leading)
                .padding(.top, 1)
        }
    }

    private func detailActions(_ item: BaseItem) -> some View {
        HStack(spacing: 10) {
            Button { showSubtitleImporter = true } label: { Label("Upload subtitle", systemImage: "arrow.up.doc") }.buttonStyle(.bordered).tint(.white)
            Button { showMediaInfo = true } label: { Label("Media info", systemImage: "info.circle") }.buttonStyle(.bordered).tint(.white)
            if let uploadMessage { Text(uploadMessage).font(.caption).foregroundStyle(.white.opacity(0.75)) }
        }
        .fileImporter(isPresented: $showSubtitleImporter, allowedContentTypes: [.text, .data], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { @MainActor in
                do {
                    let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    try await appState.api.uploadSubtitle(itemId: item.id, data: data, fileExtension: url.pathExtension, language: "eng")
                    uploadMessage = "Subtitle uploaded"
                    self.item = try await appState.api.item(id: item.id)
                } catch { uploadMessage = "Upload failed: \(error.localizedDescription)" }
            }
        }
        .popover(isPresented: $showMediaInfo) { MediaInfoDetailView(item: item) }
    }

    @ViewBuilder private func trackPanel(_ item: BaseItem, episodeStyle: Bool = false) -> some View {
        let audio = tracks(item, type: "Audio")
        let video = tracks(item, type: "Video")
        let subtitles = tracks(item, type: "Subtitle")
        if !audio.isEmpty || !video.isEmpty || !subtitles.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("PLAYBACK OPTIONS")
                    .font(.caption2.weight(.bold)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 16).padding(.vertical, 9)
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
            .background {
                if !episodeStyle {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14)) }
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                }
            }
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
                if includesOff { Button("Off") { selection.wrappedValue = -1 }.foregroundStyle(.white) }
                ForEach(tracks, id: \.id) { track in
                    Button { selection.wrappedValue = track.id } label: {
                        if selection.wrappedValue == track.id { Label(trackLabel(track), systemImage: "checkmark") }
                        else { Text(trackLabel(track)) }
                    }
                    .foregroundStyle(.white)
                }
            } label: {
                HStack(spacing: 12) {
                    Text(selectedTrackLabel(selection.wrappedValue, tracks: tracks, includesOff: includesOff))
                        .font(.callout).lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.94))
                .tint(.white)
                .padding(.horizontal, 12).frame(height: 34)
                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.13)) }
            }
            .menuStyle(.borderlessButton)
            .tint(.white)
            .frame(maxWidth: 560, alignment: .trailing)
        }.padding(.horizontal, 16).padding(.vertical, 7)
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
    private func episodeSeriesLogoURL(_ item: BaseItem) -> URL? {
        guard item.type == "Episode", let parentId = item.parentLogoItemId else { return nil }
        return appState.api.logoImageURL(itemId: parentId, tag: item.parentLogoImageTag, maxWidth: 420)
    }
    private func episodeCode(_ item: BaseItem) -> String {
        (item.parentIndexNumber.map { String(format: "S%02d", $0) } ?? "") +
        (item.indexNumber.map { String(format: "E%02d", $0) } ?? "")
    }
    private func runtime(_ item: BaseItem) -> String? {
        guard let ticks = item.runTimeTicks else { return nil }; let minutes = Int(Ticks.toSeconds(ticks) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    private func resumeSeconds(_ item: BaseItem) -> Double { Ticks.toSeconds(item.userData?.playbackPositionTicks) }
    private func playLabel(_ item: BaseItem) -> String { "Play" }
    private func play(_ item: BaseItem, startOver: Bool = false) {
        appState.playbackError = nil
        guard item.type == "Episode", let seriesId = item.seriesId else {
            nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig(),
                            startOver: startOver, audioTrack: selectedAudioTrack,
                            videoTrack: selectedVideoTrack, subtitleTrack: selectedSubtitleTrack) {
                appState.playbackError = $0
            }
            return
        }

        Task { @MainActor in
            do {
                let episodes = try await appState.api.episodes(seriesId: seriesId)
                nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig(),
                                startOver: startOver, audioTrack: selectedAudioTrack,
                                videoTrack: selectedVideoTrack, subtitleTrack: selectedSubtitleTrack,
                                queue: episodes,
                                queueIndex: episodes.firstIndex(where: { $0.id == item.id })) {
                    appState.playbackError = $0
                }
            } catch {
                pendingPlayAction = nil
                appState.playbackError = error.localizedDescription
            }
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
