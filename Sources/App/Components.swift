import SwiftUI
import JellyfinKit
import PlaybackEngine

struct CachedImage: View {
    let url: URL?
    let contentMode: ContentMode
    @State private var image: NSImage?
    @State private var loading = false

    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode) }
            else if loading { ZStack { Color.secondary.opacity(0.1); ProgressView().controlSize(.small) } }
            else { Color.secondary.opacity(0.1) }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            loading = true
            image = await MediaAssetCache.shared.image(for: url)
            loading = false
        }
    }
}

struct PosterImage: View {
    let url: URL?
    @State private var image: NSImage?
    @State private var loading = false

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else if loading { ZStack { Color.secondary.opacity(0.1); ProgressView().controlSize(.small) } }
            else { placeholder }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            loading = true
            image = await MediaAssetCache.shared.image(for: url)
            loading = false
        }
    }
    private var placeholder: some View { ZStack { Color.secondary.opacity(0.1); icon } }
    private var icon: some View { Image(systemName: "film").font(.largeTitle).foregroundStyle(.tertiary) }
}

struct PosterCard: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let item: BaseItem
    @State private var hovering = false
    @State private var playButtonHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                PosterImage(url: appState.api.primaryImageURL(for: item))
                    .frame(width: 160, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: SolfinDesign.posterRadius, style: .continuous))
                    .overlay(alignment: .bottom) { progressBar }
                    .overlay {
                        RoundedRectangle(cornerRadius: SolfinDesign.posterRadius, style: .continuous)
                            .strokeBorder(hovering ? AnyShapeStyle(LinearGradient(colors: [SolfinDesign.solarGold, SolfinDesign.solarOrange, SolfinDesign.solarRed, SolfinDesign.nebulaPurple], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(.white.opacity(0.1)), lineWidth: hovering ? 2 : 1)
                    }
                if hovering {
                    RoundedRectangle(cornerRadius: SolfinDesign.posterRadius + 8, style: .continuous)
                        .fill(RadialGradient(colors: [SolfinDesign.solarOrange.opacity(0.32), SolfinDesign.solarRed.opacity(0.18), SolfinDesign.nebulaPurple.opacity(0.22), .clear], center: .center, startRadius: 10, endRadius: 140))
                        .blur(radius: 16)
                        .padding(-14)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    Button {
                        nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig()) { appState.playbackError = $0 }
                    } label: {
                        Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(playButtonHovering ? SolfinDesign.solarOrange.opacity(0.78) : .clear, in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(playButtonHovering ? SolfinDesign.solarGold : SolfinDesign.solarOrange.opacity(0.45), lineWidth: playButtonHovering ? 2 : 1) }
                            .shadow(color: SolfinDesign.solarOrange.opacity(playButtonHovering ? 0.7 : 0.35), radius: playButtonHovering ? 26 : 18, y: 5)
                            .scaleEffect(playButtonHovering ? 1.12 : 1)
                    }
                    .buttonStyle(.plain).help("Play")
                    .onHover { playButtonHovering = $0 }
                    .animation(.easeOut(duration: 0.16), value: playButtonHovering)
                    .accessibilityLabel("Play \(item.name)")
                }
            }
            .frame(width: 160, height: 240)
            .compositingGroup()
            .shadow(color: SolfinDesign.solarOrange.opacity(hovering ? 0.22 : 0), radius: 24, y: 10)
            .shadow(color: SolfinDesign.nebulaPurple.opacity(hovering ? 0.18 : 0), radius: 30, y: 14)
            .shadow(color: .black.opacity(hovering ? 0.36 : 0.14), radius: hovering ? 18 : 6, y: hovering ? 10 : 3)
            .scaleEffect(hovering ? 1.035 : 1)
            Text(item.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if let subtitle { Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.64)).lineLimit(1) }
        }
        .frame(width: 160, alignment: .leading)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var subtitle: String? {
        if item.type == "Episode" {
            let s = item.parentIndexNumber.map { String(format: "S%02d", $0) } ?? ""
            let e = item.indexNumber.map { String(format: "E%02d", $0) } ?? ""
            return "\(item.seriesName ?? "") \(s)\(e)".trimmingCharacters(in: .whitespaces)
        }
        return item.productionYear.map(String.init)
    }
    private var accessibilityLabel: String {
        [item.name, subtitle, item.userData?.played == true ? "Watched" : nil].compactMap { $0 }.joined(separator: ", ")
    }
    @ViewBuilder private var progressBar: some View {
        if let pct = item.userData?.playedPercentage, pct > 0 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.5))
                    Rectangle().fill(LinearGradient(colors: [SolfinDesign.solarOrange, SolfinDesign.nebulaPurple], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * min(pct, 100) / 100)
                }
            }.frame(height: 4)
        }
    }
}

struct LandscapeCard: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let item: BaseItem
    @State private var hovering = false
    @State private var playButtonHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                PosterImage(url: appState.api.backdropImageURL(for: item, maxWidth: 640)
                            ?? appState.api.primaryImageURL(for: item, maxHeight: 260))
                    .frame(width: 250, height: 141)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                LinearGradient(colors: [.clear, .black.opacity(0.34)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                if hovering {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(RadialGradient(colors: [SolfinDesign.solarOrange.opacity(0.34), SolfinDesign.solarRed.opacity(0.18), SolfinDesign.nebulaPurple.opacity(0.22), .clear], center: .center, startRadius: 8, endRadius: 140))
                        .blur(radius: 16)
                        .padding(-14)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    Button {
                        nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig()) { appState.playbackError = $0 }
                    } label: {
                        Image(systemName: "play.fill").font(.headline).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(playButtonHovering ? SolfinDesign.solarOrange.opacity(0.78) : .clear, in: Circle())
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(playButtonHovering ? SolfinDesign.solarGold : SolfinDesign.solarOrange.opacity(0.45), lineWidth: playButtonHovering ? 2 : 1) }
                            .shadow(color: SolfinDesign.solarOrange.opacity(playButtonHovering ? 0.7 : 0.35), radius: playButtonHovering ? 26 : 18, y: 5)
                            .scaleEffect(playButtonHovering ? 1.12 : 1)
                    }
                    .buttonStyle(.plain).help("Play")
                    .onHover { playButtonHovering = $0 }
                    .animation(.easeOut(duration: 0.16), value: playButtonHovering)
                    .accessibilityLabel("Play \(item.name)")
                }
                if let pct = item.userData?.playedPercentage, pct > 0 {
                    GeometryReader { geo in
                        VStack { Spacer(); Rectangle().fill(LinearGradient(colors: [SolfinDesign.solarOrange, SolfinDesign.nebulaPurple], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * min(pct, 100) / 100, height: 4) }
                    }
                }
            }
            .frame(width: 250, height: 141)
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(hovering ? AnyShapeStyle(LinearGradient(colors: [SolfinDesign.solarGold, SolfinDesign.solarOrange, SolfinDesign.solarRed, SolfinDesign.nebulaPurple], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(.white.opacity(0.1)), lineWidth: hovering ? 2 : 1) }
            .compositingGroup()
            .shadow(color: SolfinDesign.solarOrange.opacity(hovering ? 0.22 : 0), radius: 24, y: 10)
            .shadow(color: SolfinDesign.nebulaPurple.opacity(hovering ? 0.18 : 0), radius: 30, y: 14)
            .shadow(color: .black.opacity(hovering ? 0.34 : 0.1), radius: hovering ? 16 : 5, y: 6)
            .scaleEffect(hovering ? 1.026 : 1)
            Text(item.type == "Episode" ? (item.seriesName ?? item.name) : item.name)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if let subtitle { Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.64)).lineLimit(1) }
        }
        .frame(width: 250, alignment: .leading)
        .contentShape(Rectangle()).onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
    }

    private var subtitle: String? {
        if item.type == "Episode" {
            let s = item.parentIndexNumber.map { String(format: "S%02d", $0) } ?? ""
            let e = item.indexNumber.map { String(format: "E%02d", $0) } ?? ""
            return [s + e, item.name].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return item.productionYear.map(String.init)
    }
}

struct LibraryBanner: View {
    @EnvironmentObject private var appState: AppState
    let item: BaseItem
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: appState.api.backdropImageURL(for: item, maxWidth: 700)
                        ?? appState.api.primaryImageURL(for: item, maxHeight: 300))
                .frame(width: 300, height: 155)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if hovering {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(RadialGradient(colors: [SolfinDesign.solarOrange.opacity(0.32), SolfinDesign.solarRed.opacity(0.18), SolfinDesign.nebulaPurple.opacity(0.22), .clear], center: .center, startRadius: 20, endRadius: 180))
                    .blur(radius: 18)
                    .padding(-16)
                    .transition(.opacity)
            }
            Text(item.name).font(.title.weight(.semibold)).foregroundStyle(.white).padding(18)
        }
        .frame(width: 300, height: 155)
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(hovering ? AnyShapeStyle(LinearGradient(colors: [SolfinDesign.solarGold, SolfinDesign.solarOrange, SolfinDesign.solarRed, SolfinDesign.nebulaPurple], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(.white.opacity(0.1)), lineWidth: hovering ? 2 : 1) }
        .compositingGroup()
        .shadow(color: SolfinDesign.solarOrange.opacity(hovering ? 0.22 : 0), radius: 24, y: 10)
        .shadow(color: SolfinDesign.nebulaPurple.opacity(hovering ? 0.16 : 0), radius: 30, y: 14)
        .scaleEffect(hovering ? 1.025 : 1).onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hovering)
    }
}

struct BackdropHero: View {
    let url: URL?
    let height: CGFloat
    var body: some View {
        ZStack(alignment: .bottom) {
            if let url {
                CachedImage(url: url).frame(height: height).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.22), Color(nsColor: .windowBackgroundColor)],
                               startPoint: .top, endPoint: .bottom).frame(height: height)
            }
        }.frame(maxWidth: .infinity).frame(height: url == nil ? 0 : height)
    }
}

private struct SubtitleEditorView: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @Environment(\.dismiss) private var dismiss
    @State private var delay = 0.0
    @State private var position = 100.0
    @State private var scale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("Edit subtitles").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            Text("Changes apply immediately to the active mpv session.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Timing"); Spacer(); Text(String(format: "%+.1f s", delay)).monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $delay, in: -10...10, step: 0.1) { _ in nowPlaying.setSubtitleDelay(delay) }
                HStack { Button("−0.5 s") { delay -= 0.5; nowPlaying.setSubtitleDelay(delay) }; Button("Reset") { delay = 0; nowPlaying.setSubtitleDelay(0) }; Button("+0.5 s") { delay += 0.5; nowPlaying.setSubtitleDelay(delay) } }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Vertical position"); Spacer(); Text("\(Int(position))%").foregroundStyle(.secondary) }
                Slider(value: $position, in: 0...100, step: 1) { _ in nowPlaying.setSubtitlePosition(Int(position)) }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Size"); Spacer(); Text(String(format: "%.1f×", scale)).foregroundStyle(.secondary) }
                Slider(value: $scale, in: 0.5...2, step: 0.05) { _ in nowPlaying.setSubtitleScale(scale) }
            }
        }.padding(28).frame(width: 430).onAppear { delay = 0; position = 100; scale = 1 }
    }
}

private struct MediaInfoView: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Media information").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            info("Title", nowPlaying.itemName ?? "Unknown")
            info("Duration", duration)
            info("Position", durationText(nowPlaying.positionSeconds))
            info("Seekable", nowPlaying.isSeekable ? "Yes" : "No")
            Divider()
            Text("Tracks").font(.headline)
            ForEach(Array(nowPlaying.mediaStreams.enumerated()), id: \.offset) { _, stream in
                HStack {
                    Text(stream.type ?? "Track").foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                    Text(stream.displayTitle ?? stream.language ?? stream.codec ?? "Unknown")
                    Spacer()
                    if let codec = stream.codec { Text(codec.uppercased()).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.padding(28).frame(width: 500).fixedSize(horizontal: false, vertical: true)
    }
    private var duration: String { durationText(nowPlaying.durationSeconds) }
    private func durationText(_ value: Double) -> String { let s = max(0, Int(value)); return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
    private func info(_ key: String, _ value: String) -> some View { HStack { Text(key).foregroundStyle(.secondary); Spacer(); Text(value) } }
}

struct NowPlayingBar: View {
    @EnvironmentObject private var nowPlaying: NowPlaying
    @State private var dragging = false
    @State private var draftPosition = 0.0
    @State private var showSubtitleEditor = false
    @State private var showMediaInfo = false

    var body: some View {
        if nowPlaying.isActive, let name = nowPlaying.itemName {
            HStack(spacing: 14) {
                ZStack {
                    PosterImage(url: nowPlaying.artworkURL).frame(width: 52, height: 52).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    if nowPlaying.isQueueTransitioning {
                        RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.38))
                        ProgressView().controlSize(.small).scaleEffect(0.82).tint(.white)
                    }
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(nowPlaying.subtitle ?? nowPlaying.state.rawValue.capitalized)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(width: 180, alignment: .leading)
                Text(timeString(displayPosition)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Slider(value: Binding(get: { displayPosition }, set: { draftPosition = $0 }),
                       in: 0...max(nowPlaying.durationSeconds, 1), onEditingChanged: { editing in
                    dragging = editing
                    if !editing { nowPlaying.seek(to: draftPosition) }
                }).disabled(!nowPlaying.isSeekable).accessibilityLabel("Playback position")
                Text("−\(timeString(max(0, nowPlaying.durationSeconds - displayPosition)))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                control("backward.end.fill", "Previous episode", enabled: nowPlaying.hasPreviousInQueue && !nowPlaying.isQueueTransitioning) { nowPlaying.playPrevious() }
                control("gobackward.15", "Back 15 seconds", enabled: !nowPlaying.isQueueTransitioning) { nowPlaying.skip(seconds: -15) }
                control(nowPlaying.state == .paused ? "play.fill" : "pause.fill",
                        nowPlaying.state == .paused ? "Play" : "Pause", enabled: !nowPlaying.isQueueTransitioning) { nowPlaying.togglePause() }
                control("goforward.30", "Forward 30 seconds", enabled: !nowPlaying.isQueueTransitioning) { nowPlaying.skip(seconds: 30) }
                control("forward.end.fill", "Next episode", enabled: nowPlaying.hasNextInQueue && !nowPlaying.isQueueTransitioning) { nowPlaying.playNext() }
                if nowPlaying.isQueueTransitioning {
                    ProgressView().controlSize(.small).scaleEffect(0.72)
                }
                trackMenu.disabled(nowPlaying.isQueueTransitioning).opacity(nowPlaying.isQueueTransitioning ? 0.35 : 1)
                Button { showSubtitleEditor = true } label: {
                    Image(systemName: "textformat.size").frame(width: 26, height: 26)
                }
                .buttonStyle(.plain).help("Edit subtitles")
                .disabled(nowPlaying.isQueueTransitioning || nowPlaying.subtitleTracks.isEmpty)
                Button { showMediaInfo = true } label: {
                    Image(systemName: "info.circle").frame(width: 26, height: 26)
                }
                .buttonStyle(.plain).help("Media information")
                control("xmark", "Stop") { nowPlaying.stop() }
            }
            .sheet(isPresented: $showSubtitleEditor) { SubtitleEditorView() }
            .popover(isPresented: $showMediaInfo) { MediaInfoView() }
            .padding(10)
            .glassSurface(cornerRadius: 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var trackMenu: some View {
        Menu {
            if !nowPlaying.audioTracks.isEmpty {
                Section("Audio") {
                    ForEach(nowPlaying.audioTracks, id: \.id) { track in
                        Button { nowPlaying.selectAudioTrack(track.id) } label: {
                            if nowPlaying.selectedAudioTrack == track.id { Label(trackName(track), systemImage: "checkmark") }
                            else { Text(trackName(track)) }
                        }
                    }
                }
            }
            if !nowPlaying.subtitleTracks.isEmpty {
                Section("Subtitles") {
                    Button { nowPlaying.selectSubtitleTrack(nil) } label: {
                        if nowPlaying.selectedSubtitleTrack == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                    }
                    ForEach(nowPlaying.subtitleTracks, id: \.id) { track in
                        Button { nowPlaying.selectSubtitleTrack(track.id) } label: {
                            if nowPlaying.selectedSubtitleTrack == track.id { Label(trackName(track), systemImage: "checkmark") }
                            else { Text(trackName(track)) }
                        }
                    }
                }
            }
            if nowPlaying.videoTracks.count > 1 {
                Section("Video") {
                    ForEach(nowPlaying.videoTracks, id: \.id) { track in
                        Button { nowPlaying.selectVideoTrack(track.id) } label: {
                            if nowPlaying.selectedVideoTrack == track.id { Label(trackName(track), systemImage: "checkmark") }
                            else { Text(trackName(track)) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "captions.bubble")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .frame(height: 26)
            .padding(.horizontal, 7)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Playback tracks")
    }

    private func trackName(_ track: (id: Int, stream: MediaStream)) -> String {
        track.stream.displayTitle ?? track.stream.language ?? "Track \(track.id)"
    }
    private var displayPosition: Double { dragging ? draftPosition : nowPlaying.positionSeconds }
    private func control(_ icon: String, _ label: String, enabled: Bool = true,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 26, height: 26) }
            .buttonStyle(.plain).accessibilityLabel(label)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }
    private func timeString(_ seconds: Double) -> String {
        let value = max(0, Int(seconds)); let hours = value / 3600
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, value % 3600 / 60, value % 60)
                         : String(format: "%d:%02d", value / 60, value % 60)
    }
}
