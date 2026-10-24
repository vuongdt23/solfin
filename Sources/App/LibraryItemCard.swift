import SwiftUI
import JellyfinKit
import PlaybackEngine

/// Navigation and playback are sibling controls, never a Button inside a NavigationLink.
struct LibraryItemCard: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    let item: BaseItem
    let cardType: LibraryCardType
    let size: LibraryCardSize
    @State private var hovering = false
    @State private var playbackHovering = false
    @FocusState private var focused: Bool
    @FocusState private var playbackFocused: Bool
    @State private var resolvedEpisode: BaseItem?
    @State private var episodes: [BaseItem] = []
    @State private var resolving = false
    @State private var resolutionError: String?

    private var imageWidth: CGFloat {
        switch cardType {
        case .poster: size.posterWidth
        case .banner: size.bannerWidth
        case .thumbnail: size.bannerWidth
        }
    }
    private var imageHeight: CGFloat {
        switch cardType {
        case .poster: size.posterWidth * 1.5
        case .banner: size.bannerHeight
        case .thumbnail: size.bannerHeight
        }
    }
    private var active: Bool { hovering || focused || playbackFocused }
    private var cardHelp: String {
        var lines = [item.name, item.viewingStatus]
        if item.type != "Series", let ticks = item.runTimeTicks, ticks > 0 {
            lines.append("\(Int(Ticks.toSeconds(ticks) / 60)) min")
        }
        return lines.joined(separator: "\n")
    }
    private var playbackTitle: String {
        if item.type == "Series" {
            return resolvedEpisode?.playbackActionTitle ?? (resolving ? "Finding episode…" : "Play next episode")
        }
        return item.playbackActionTitle
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            NavigationLink(value: item) {
                cardArtwork
                    .contentShape(Rectangle())
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(focused ? .white.opacity(0.5) : .clear, lineWidth: 2)
                            .allowsHitTesting(false)
                            .frame(width: imageWidth, height: imageHeight)
                    }
                    .cardHoverEffect(isActive: active, lift: 6, scale: 1.03)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .focused($focused)
            .help(cardHelp)
            .accessibilityLabel("Open \(item.name), \(item.viewingStatus)")

            VStack {
                HStack {
                    Spacer()
                    if item.userData?.played == true {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .padding(7)
                            .background(.black.opacity(0.72), in: Circle())
                            .padding(8)
                            .accessibilityLabel("Watched")
                    }
                }
                Spacer(minLength: 0)
                if let progress = item.viewingProgress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.black.opacity(0.6))
                            Rectangle().fill(SolfinDesign.solarGold)
                                .frame(width: proxy.size.width * progress)
                        }
                    }.frame(height: 4)
                }
            }
            .frame(width: imageWidth, height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .allowsHitTesting(false)

            // Keep this control in the accessibility tree even when pointer chrome is hidden.
            Button { Task { await play() } } label: {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().strokeBorder(playbackHovering ? SolfinDesign.solarGold : SolfinDesign.solarOrange.opacity(0.45), lineWidth: playbackHovering ? 2 : 1) }
                    .background(playbackHovering ? SolfinDesign.solarOrange.opacity(0.78) : .clear, in: Circle())
                    .shadow(color: SolfinDesign.solarOrange.opacity(playbackHovering ? 0.7 : 0.35), radius: playbackHovering ? 26 : 18, y: 5)
                    .scaleEffect(playbackHovering ? 1.12 : 1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .focused($playbackFocused)
            .onHover { playbackHovering = $0 }
            .animation(.easeOut(duration: 0.16), value: playbackHovering)
            .overlay { Circle().strokeBorder(playbackFocused ? SolfinDesign.solarGold : .clear, lineWidth: 3) }
            .opacity(active ? 1 : 0)
            .offset(x: (imageWidth - 46) / 2, y: (imageHeight - 46) / 2)
            .allowsHitTesting(active)
            .accessibilityHidden(false)
            .help(resolutionError ?? playbackTitle)
            .accessibilityLabel("\(playbackTitle), \(item.name)")
            .disabled(nowPlaying.isLaunching)
        }
        .onHover { hovering = $0 }
        .task(id: active) {
            if active, item.type == "Series", resolvedEpisode == nil { await resolveEpisode() }
        }
    }

    @ViewBuilder private var cardArtwork: some View {
        switch cardType {
        case .poster: PosterCard(item: item, size: LibraryDensity(size: size), showsPlaybackControls: false)
        case .thumbnail: ThumbnailCard(item: item, size: size)
        case .banner: LandscapeCard(item: item, size: size, showsPlaybackControls: false)
        }
    }

    @MainActor private func resolveEpisode() async {
        guard !resolving else { return }
        resolving = true
        defer { resolving = false }
        do {
            let available = try await appState.api.episodes(seriesId: item.id)
            guard !Task.isCancelled else { return }
            episodes = available
            resolvedEpisode = available.first { $0.resumePositionSeconds > 0 }
                ?? available.first { $0.userData?.played != true }
                ?? available.first
            resolutionError = resolvedEpisode == nil ? "No playable episodes" : nil
        } catch {
            if !Task.isCancelled { resolutionError = error.localizedDescription }
        }
    }

    @MainActor private func play() async {
        guard !nowPlaying.isLaunching else { return }
        appState.playbackError = nil
        if item.type == "Series" {
            // Hover prefetch may still be in flight when the user clicks.
            while resolving {
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
            }
            if resolvedEpisode == nil { await resolveEpisode() }
            guard let resolvedEpisode else {
                appState.playbackError = resolutionError ?? "No playable episodes"
                return
            }
            nowPlaying.play(item: resolvedEpisode, api: appState.api, config: appState.makePlaybackConfig(),
                            startOver: resolvedEpisode.userData?.played == true, queue: episodes, queueIndex: episodes.firstIndex { $0.id == resolvedEpisode.id }) {
                appState.playbackError = $0
            }
        } else {
            nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig(),
                            startOver: item.userData?.played == true) {
                appState.playbackError = $0
            }
        }
    }
}
