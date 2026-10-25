import SwiftUI
import UniformTypeIdentifiers
import JellyfinKit
import PlaybackEngine

struct ItemDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let itemId: String
    var sidebarLeadingInset: CGFloat = 64

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
        GeometryReader { proxy in
            let layout = DetailLayout(viewport: proxy.size, railWidth: sidebarLeadingInset)
            ScrollView {
                if let item { immersiveDetail(item, layout: layout) }
                else if let loadError {
                    EmptyContentView(title: "Details unavailable", message: loadError,
                                     systemImage: "wifi.exclamationmark") { Task { await load() } }
                        .padding(.leading, layout.leadingInset)
                        .padding(.trailing, layout.trailingInset)
                } else { detailSkeleton }
            }
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

    private func immersiveDetail(_ item: BaseItem, layout: DetailLayout) -> some View {
        let isEpisode = item.type == "Episode"
        return VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            if isEpisode {
                episodeContent(item, layout: layout)
                    .padding(.top, layout.topSpacing)
                    .padding(.bottom, layout.sectionSpacing)
                    .frame(minHeight: max(0, layout.viewport.height - 200), alignment: .center)
                if previousEpisode != nil || nextEpisode != nil {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("More from \(item.seriesName ?? "this series")")
                            .font(DetailTypography.font(DetailTypography.sectionTitle, weight: .semibold))
                        adjacentEpisodeSection(width: layout.contentWidth)
                    }
                }
            } else {
                movieCopy(item, layout: layout)
                    .padding(.top, layout.topSpacing)
            }
        }
        .frame(width: layout.contentWidth, alignment: .leading)
        .padding(.leading, layout.leadingInset)
        .padding(.trailing, layout.trailingInset)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: layout.viewport.height, alignment: isEpisode ? .topLeading : .bottomLeading)
        .background(alignment: .topLeading) {
            // Background geometry never dictates the scrollable content height.
            // The original art can overflow while expanded text stays in flow.
            GeometryReader { proxy in
                let size = CGSize(width: layout.viewport.width, height: max(layout.artworkHeight, proxy.size.height))
                ZStack {
                    if isEpisode { episodeBackdrop(item, size: size) }
                    else { backdrop(item, size: size) }
                    solarAura
                    if isEpisode { cinematicScrim } else { movieScrim }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
            }
        }
    }

    private func movieCopy(_ item: BaseItem, layout: DetailLayout) -> some View {
        let columns = layout.usesColumns
        return (columns ? AnyLayout(HStackLayout(alignment: .bottom, spacing: layout.columnGap))
                        : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))) {
            VStack(alignment: .leading, spacing: 20) {
                identity(item, layout: layout)
                overview(item)
                playbackError
            }
            .frame(width: layout.copyWidth, alignment: .leading)
            playbackOptions(item)
                .frame(width: layout.secondaryWidth, alignment: .leading)
        }
    }

    private func episodeContent(_ item: BaseItem, layout: DetailLayout) -> some View {
        Group {
            if layout.usesColumns {
                HStack(alignment: .center, spacing: layout.columnGap) {
                    VStack(alignment: .leading, spacing: 20) {
                        identity(item, layout: layout)
                        overview(item)
                        playbackError
                        playbackOptions(item)
                    }
                    .frame(width: layout.copyWidth, alignment: .leading)
                    episodeStill(item, layout: layout)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: layout.collectionWidth, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    identity(item, layout: layout)
                    episodeStill(item, layout: layout)
                    overview(item)
                    playbackError
                    playbackOptions(item)
                }
                .frame(width: layout.copyWidth, alignment: .leading)
            }
        }
    }

    private func playbackOptions(_ item: BaseItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            trackPanel(item, episodeStyle: item.type == "Episode")
            detailActions(item)
        }
    }

    @ViewBuilder private func backdrop(_ item: BaseItem, size: CGSize) -> some View {
        let bannerHeight = size.height
        if let url = backdropURL(item) {
            ZStack {
                Color.black
                // Match the series banner: a soft, enlarged edge layer fills the
                // wide canvas while the complete original artwork stays visible.
                CachedImage(url: url, contentMode: .fill)
                    .scaleEffect(1.12)
                    .blur(radius: 28)
                    .opacity(0.72)
                    .overlay(Color.black.opacity(0.28))
                CachedImage(url: url, contentMode: .fit)
            }
            .frame(width: size.width, height: bannerHeight, alignment: .top)
            .clipped()
        } else if let poster = appState.api.playablePosterURL(for: item, maxHeight: nil) {
            ZStack {
                Color.black
                CachedImage(url: poster, contentMode: .fill)
                    .scaleEffect(1.12)
                    .blur(radius: 28)
                    .opacity(0.72)
                    .overlay(Color.black.opacity(0.28))
                CachedImage(url: poster, contentMode: .fit)
            }
            .frame(width: size.width, height: bannerHeight, alignment: .top)
            .clipped()
        } else {
            LinearGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.38), SolfinDesign.spaceBlack],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: size.width, height: bannerHeight)
        }
    }

    private func episodeBackdrop(_ item: BaseItem, size: CGSize) -> some View {
        ZStack {
            if let hero = appState.api.seriesHeroBackdropURL(for: item, maxWidth: nil) {
                ZStack {
                    CachedImage(url: hero, contentMode: .fill)
                        .scaleEffect(1.12)
                        .blur(radius: 28)
                        .opacity(0.72)
                        .overlay(Color.black.opacity(0.28))
                    CachedImage(url: hero, contentMode: .fit)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            } else if let poster = appState.api.playablePosterURL(for: item, maxHeight: nil) {
                ZStack {
                    CachedImage(url: poster, contentMode: .fill)
                        .scaleEffect(1.12)
                        .blur(radius: 28)
                        .opacity(0.72)
                        .overlay(Color.black.opacity(0.28))
                    CachedImage(url: poster, contentMode: .fit)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            } else {
                Color.black
            }
        }
    }

    private func episodeStill(_ item: BaseItem, layout: DetailLayout) -> some View {
        let stillURL = appState.api.episodeArtworkURL(for: item, maxWidth: 1600)
        let aspect = max(1.25, min(2.0, item.primaryImageAspectRatio ?? (16.0 / 9.0)))
        let width = layout.episodeStillWidth(aspectRatio: aspect)
        let height = width / aspect
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return CachedImage(url: stillURL, contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 24, y: 14)
            .accessibilityLabel("Still from \(item.name)")
    }

    private var movieScrim: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.64), location: 0),
                                   .init(color: .black.opacity(0.28), location: 0.38),
                                   .init(color: .clear, location: 0.72)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .clear, location: 0.3),
                                   .init(color: .black.opacity(0.45), location: 0.66),
                                   .init(color: .black.opacity(0.88), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }

    private var cinematicScrim: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.18)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.5), .clear, .black.opacity(0.08)],
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

    private func identity(_ item: BaseItem, layout: DetailLayout) -> some View {
        let isEpisode = item.type == "Episode"
        let seriesLogo = isEpisode ? episodeSeriesLogoURL(item) : nil
        return SolarHeroIdentity(
            item: item,
            context: isEpisode ? (seriesLogo == nil ? item.seriesName : nil) : contextTitle(item),
            episodeCode: isEpisode ? episodeCode(item) : nil,
            runtime: runtime(item),
            overview: nil,
            logoURL: seriesLogo,
            logoWidth: isEpisode && seriesLogo != nil ? min(280, layout.copyWidth) : layout.logoWidth,
            logoHeight: isEpisode ? 72 : layout.logoHeight,
            fallbackSize: layout.titleSize,
            lookupDefaultLogo: !isEpisode,
            subtitle: isEpisode && seriesLogo != nil ? item.name : nil,
            wrapsMetadata: true
        ) {
            actions(item)
        }
    }

    private func actions(_ item: BaseItem) -> some View {
        let isWaitingForLaunch = pendingPlayAction != nil
        return DetailFlowLayout(spacing: 10) {
            playButton(item, action: .primary, title: playLabel(item), systemImage: "play.fill",
                       isPrimary: true, isBusy: pendingPlayAction == .primary && isWaitingForLaunch,
                       hovering: primaryPlayButtonHovering)
                .onHover { primaryPlayButtonHovering = $0 }

            if item.resumePositionSeconds > 0 {
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
            play(item, startOver: action == .startOver || item.userData?.played == true)
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
            .font(DetailTypography.font(DetailTypography.control, weight: .semibold))
            .padding(.horizontal, isPrimary ? 20 : 16)
            .frame(height: item.type == "Episode" ? 42 : 48)
            .contentShape(Capsule())
        }
        .buttonStyle(SolarPillButtonStyle(hovering: hovering, isPrimary: isPrimary))
        .opacity(pendingPlayAction == nil || isBusy ? 1 : 0.62)
    }

    @ViewBuilder private func overview(_ item: BaseItem) -> some View {
        if let overview = item.overview, !overview.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(overview)
                    .font(DetailTypography.font(item.type == "Episode" ? DetailTypography.supporting : DetailTypography.body))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .lineLimit(overviewExpanded ? nil : (item.type == "Episode" ? 3 : 5))
                    .frame(maxWidth: 760, alignment: .leading)
                if overview.count > 140 {
                    Button(overviewExpanded ? "Show Less" : "More") { withAnimation { overviewExpanded.toggle() } }
                        .buttonStyle(.plain).font(DetailTypography.font(DetailTypography.supporting, weight: .semibold)).foregroundStyle(.white)
                }
            }.frame(maxWidth: 760, alignment: .leading)
                .padding(.top, 1)
        }
    }

    private func detailActions(_ item: BaseItem) -> some View {
        DetailFlowLayout(spacing: 10) {
            Button { showSubtitleImporter = true } label: {
                Label("Upload subtitle", systemImage: "arrow.up.doc")
                    .font(DetailTypography.font(DetailTypography.control, weight: .medium))
            }.buttonStyle(.bordered).tint(.white)
            Button { showMediaInfo = true } label: {
                Label("Media info", systemImage: "info.circle")
                    .font(DetailTypography.font(DetailTypography.control, weight: .medium))
            }.buttonStyle(.bordered).tint(.white)
            if let uploadMessage { Text(uploadMessage).font(DetailTypography.font(DetailTypography.supporting)).foregroundStyle(.white.opacity(0.75)) }
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
                    .font(DetailTypography.font(DetailTypography.trackHeading, weight: .bold)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                Divider().overlay(.white.opacity(0.1))
                if !video.isEmpty {
                    trackRow(title: "Video", icon: "film", selection: $selectedVideoTrack,
                             tracks: video, includesOff: false)
                    if !audio.isEmpty || !subtitles.isEmpty {
                        Divider().overlay(.white.opacity(0.08)).padding(.leading, 52)
                    }
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
                .font(DetailTypography.font(DetailTypography.metadata, weight: .medium))
                .frame(width: 24).foregroundStyle(.white.opacity(0.72))
            Text(title).font(DetailTypography.font(DetailTypography.metadata, weight: .medium)).foregroundStyle(.white.opacity(0.84))
                .fixedSize()
            Spacer(minLength: 4)
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
                        .font(DetailTypography.font(DetailTypography.metadata))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(DetailTypography.font(DetailTypography.micro, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.94))
                .tint(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 34)
                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.13)) }
            }
            .menuStyle(.borderlessButton)
            .tint(.white)
            .frame(maxWidth: 560, alignment: .trailing)
            .help(selectedTrackLabel(selection.wrappedValue, tracks: tracks, includesOff: includesOff))
        }.padding(.horizontal, 16).padding(.vertical, 7)
    }

    private func adjacentEpisodeSection(width: CGFloat) -> some View {
        let columns = width >= 760
        return (columns ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                        : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))) {
            if let previousEpisode { adjacentCard(previousEpisode, label: "Previous Episode") }
            if let nextEpisode { adjacentCard(nextEpisode, label: "Next Episode") }
        }
    }
    private func adjacentCard(_ episode: BaseItem, label: String) -> some View {
        NavigationLink(value: episode) {
            HStack(spacing: 14) {
                PosterImage(url: appState.api.primaryImageURL(for: episode, maxHeight: 180))
                    .frame(width: 132, height: 74).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(label.uppercased()).font(DetailTypography.font(DetailTypography.micro, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    Text(episode.name).font(DetailTypography.font(DetailTypography.cardTitle, weight: .semibold)).lineLimit(2)
                    Text(episodeCode(episode)).font(DetailTypography.font(DetailTypography.supporting)).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: 440, alignment: .leading)
            .cardHoverEffect(lift: 5, scale: 1.02)
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var playbackError: some View {
        if let error = appState.playbackError {
            Label(error, systemImage: "exclamationmark.circle.fill").font(DetailTypography.font(DetailTypography.supporting)).foregroundStyle(.red).padding(12)
                .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var detailSkeleton: some View {
        VStack(spacing: 26) {
            Spacer()
            RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.12)).frame(maxWidth: 520, minHeight: 110)
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
    private func playLabel(_ item: BaseItem) -> String {
        item.resumePositionSeconds > 0 ? "Resume · \(item.resumeTimestamp)" : "Play"
    }
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
        overviewExpanded = false; uploadMessage = nil
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
        selectedAudioTrack = preferredTrackID(
            language: appState.preferredAudioLanguage,
            tracks: audio
        )
            ?? source?.defaultAudioStreamIndex
            ?? audio.first(where: { $0.stream.isDefault == true })?.id
            ?? audio.first?.id
        selectedVideoTrack = video.first(where: { $0.stream.isDefault == true })?.id ?? video.first?.id
        selectedSubtitleTrack = preferredTrackID(
            language: appState.preferredSubtitleLanguage,
            tracks: subtitles
        )
            ?? source?.defaultSubtitleStreamIndex
            ?? subtitles.first(where: { $0.stream.isDefault == true })?.id
            ?? -1
    }

    private func preferredTrackID(language: String, tracks: [(id: Int, stream: MediaStream)]) -> Int? {
        guard !language.isEmpty else { return nil }
        return tracks.first { stream in
            guard let value = stream.stream.language else { return false }
            return value.lowercased().split(separator: "-").first
                == language.lowercased().split(separator: "-").first
        }?.id
    }
}
