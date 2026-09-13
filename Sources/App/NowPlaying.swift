import Foundation
import SwiftUI
import JellyfinKit
import PlaybackEngine

/// Observable wrapper around the active PlaybackController for the "Now Playing" strip.
/// Also drives next-episode autoplay when an episode finishes naturally.
@MainActor
final class NowPlaying: ObservableObject {
    @Published var itemName: String?
    @Published var subtitle: String?
    @Published var state: PlaybackController.State = .idle
    @Published var positionSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var isSeekable = false
    @Published var artworkURL: URL?
    @Published var mediaStreams: [MediaStream] = []
    @Published var selectedAudioTrack: Int?
    @Published var selectedVideoTrack: Int?
    @Published var selectedSubtitleTrack: Int?
    @AppStorage("solfin.autoplayNext") var autoplayNext: Bool = true

    private var controller: PlaybackController?
    private var progressTask: Task<Void, Never>?

    // Context retained so we can autoplay the next episode.
    private var api: APIClient?
    private var config: PlaybackController.Config?
    private var currentItem: BaseItem?
    private var onError: ((String) -> Void)?
    private var userStopped = false

    var isActive: Bool {
        controller != nil && state != .stopped && state != .idle
    }

    func play(item: BaseItem, api: APIClient, config: PlaybackController.Config,
              startOver: Bool = false, audioTrack: Int? = nil,
              videoTrack: Int? = nil, subtitleTrack: Int? = nil,
              onError: @escaping (String) -> Void) {
        // Tear down any previous session first (mark so its stop doesn't cancel autoplay).
        userStopped = true
        progressTask?.cancel()
        controller?.stop()
        userStopped = false

        self.api = api
        self.config = config
        self.currentItem = item
        self.onError = onError

        let c = PlaybackController(api: api, item: item, config: config,
                                   startOverride: startOver ? 0 : nil)
        itemName = item.name
        subtitle = Self.episodeSubtitle(item)
        state = .starting
        positionSeconds = Ticks.toSeconds(item.userData?.playbackPositionTicks)
        durationSeconds = Ticks.toSeconds(item.runTimeTicks)
        artworkURL = api.playablePosterURL(for: item, maxHeight: 160)
        let itemSource = item.mediaSources?.first
        mediaStreams = itemSource?.mediaStreams ?? []
        selectedAudioTrack = audioTrack
            ?? defaultTrackIndex(type: "Audio", serverDefault: itemSource?.defaultAudioStreamIndex)
        selectedVideoTrack = videoTrack ?? defaultTrackIndex(type: "Video")
        selectedSubtitleTrack = subtitleTrack == -1
            ? nil
            : (subtitleTrack ?? defaultTrackIndex(type: "Subtitle",
                                                  serverDefault: itemSource?.defaultSubtitleStreamIndex))
        isSeekable = durationSeconds > 0

        var appliedInitialTracks = false
        c.onStateChange = { [weak self] state, pos in
            Task { @MainActor in
                self?.state = state
                self?.positionSeconds = pos
                self?.updateProgressClock(for: state)
                if state == .playing, !appliedInitialTracks {
                    appliedInitialTracks = true
                    if let audioTrack { c.selectAudioTrack(id: audioTrack) }
                    if let videoTrack { c.selectVideoTrack(id: videoTrack) }
                    if let subtitleTrack {
                        c.selectSubtitleTrack(id: subtitleTrack == -1 ? nil : subtitleTrack)
                    }
                }
            }
        }
        c.onMediaInfoChange = { [weak self] duration, seekable in
            Task { @MainActor in
                if duration > 0 { self?.durationSeconds = duration }
                self?.isSeekable = seekable
            }
        }
        c.onPlaybackStreams = { [weak self] streams, defaultAudio, defaultSubtitle in
            Task { @MainActor in
                guard let self else { return }
                self.mediaStreams = streams
                self.selectedAudioTrack = audioTrack
                    ?? self.defaultTrackIndex(type: "Audio", serverDefault: defaultAudio)
                self.selectedVideoTrack = videoTrack ?? self.defaultTrackIndex(type: "Video")
                self.selectedSubtitleTrack = subtitleTrack == -1
                    ? nil
                    : (subtitleTrack ?? self.defaultTrackIndex(type: "Subtitle",
                                                               serverDefault: defaultSubtitle))
            }
        }
        c.onError = { err in
            Task { @MainActor in onError(err.localizedDescription) }
        }
        c.onFinished = { [weak self] naturalEnd in
            Task { @MainActor in self?.handleFinished(naturalEnd: naturalEnd) }
        }
        controller = c
        c.start()
    }

    func stop() {
        userStopped = true
        progressTask?.cancel()
        controller?.stop()
    }

    func togglePause() {
        guard state == .playing || state == .paused else { return }
        let paused = state != .paused
        state = paused ? .paused : .playing
        updateProgressClock(for: state)
        controller?.setPaused(paused)
    }
    func skip(seconds: Double) { controller?.seek(relativeSeconds: seconds) }
    func seek(to seconds: Double) {
        positionSeconds = seconds
        controller?.seek(to: seconds)
    }
    func selectAudioTrack(_ id: Int) { selectedAudioTrack = id; controller?.selectAudioTrack(id: id) }
    func selectVideoTrack(_ id: Int) { selectedVideoTrack = id; controller?.selectVideoTrack(id: id) }
    func selectSubtitleTrack(_ id: Int?) { selectedSubtitleTrack = id; controller?.selectSubtitleTrack(id: id) }

    var audioTracks: [(id: Int, stream: MediaStream)] { tracks(type: "Audio") }
    var videoTracks: [(id: Int, stream: MediaStream)] { tracks(type: "Video") }
    var subtitleTracks: [(id: Int, stream: MediaStream)] { tracks(type: "Subtitle") }

    private func tracks(type: String) -> [(id: Int, stream: MediaStream)] {
        mediaStreams.filter { $0.type == type }.enumerated().map { ordinal, stream in
            // Index is Jellyfin's stable stream identity. The ordinal fallback keeps
            // compatibility with old/incomplete server responses.
            (stream.index ?? ordinal + 1, stream)
        }
    }
    private func defaultTrackIndex(type: String, serverDefault: Int? = nil) -> Int? {
        let matching = tracks(type: type)
        if let serverDefault, matching.contains(where: { $0.id == serverDefault }) {
            return serverDefault
        }
        if type == "Subtitle" {
            return matching.first(where: { $0.stream.isDefault == true })?.id
        }
        return matching.first(where: { $0.stream.isDefault == true })?.id ?? matching.first?.id
    }

    private func updateProgressClock(for state: PlaybackController.State) {
        progressTask?.cancel()
        guard state == .playing else { return }
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.25))
                guard !Task.isCancelled, let self, self.state == .playing else { return }
                self.positionSeconds = min(self.positionSeconds + 0.25,
                                           self.durationSeconds > 0 ? self.durationSeconds : .greatestFiniteMagnitude)
            }
        }
    }

    // MARK: - Autoplay

    private func handleFinished(naturalEnd: Bool) {
        let finished = currentItem
        let stoppedByUser = userStopped
        userStopped = false

        // Only chain when the episode played to completion and the user didn't stop it.
        guard naturalEnd, !stoppedByUser,
              autoplayNext,
              let finished, finished.type == "Episode",
              let api, let config else {
            clearIfIdle()
            return
        }

        Task { @MainActor in
            do {
                if let next = try await api.nextEpisode(after: finished) {
                    play(item: next, api: api, config: config,
                         onError: onError ?? { _ in })
                } else {
                    clearIfIdle()
                }
            } catch {
                onError?(error.localizedDescription)
                clearIfIdle()
            }
        }
    }

    private func clearIfIdle() {
        if state == .stopped {
            progressTask?.cancel()
            itemName = nil
            subtitle = nil
            artworkURL = nil
            durationSeconds = 0
            isSeekable = false
            mediaStreams = []
            selectedAudioTrack = nil
            selectedVideoTrack = nil
            selectedSubtitleTrack = nil
        }
    }

    static func episodeSubtitle(_ item: BaseItem) -> String? {
        guard item.type == "Episode" else { return nil }
        let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
        let e = item.indexNumber.map { "E\($0)" } ?? ""
        return "\(item.seriesName ?? "") · \(s)\(e)".trimmingCharacters(in: .whitespaces)
    }
}
