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
    @Published var isLaunching = false
    @Published var isQueueTransitioning = false
    @Published var queue: [BaseItem] = []
    @Published var queueIndex: Int = 0
    @AppStorage("solfin.autoplayNext") var autoplayNext: Bool = true

    private var controller: PlaybackController?
    private var progressTask: Task<Void, Never>?

    // Context retained so we can autoplay the next episode.
    private var api: APIClient?
    private var config: PlaybackController.Config?
    private var currentItem: BaseItem?
    private var onError: ((String) -> Void)?
    private var userStopped = false
    private var playbackGeneration = UUID()

    var isActive: Bool {
        // Do not surface the Now Playing bar until mpv has actually launched and
        // playback has transitioned out of the preflight/network startup phase.
        controller != nil && (state == .playing || state == .paused || (state == .starting && !isLaunching) || isQueueTransitioning)
    }

    func play(item: BaseItem, api: APIClient, config: PlaybackController.Config,
              startOver: Bool = false, audioTrack: Int? = nil,
              videoTrack: Int? = nil, subtitleTrack: Int? = nil,
              queue: [BaseItem] = [], queueIndex: Int? = nil,
              onError: @escaping (String) -> Void) {
        // Invalidate callbacks from any previous mpv session before stopping it; its
        // async teardown can otherwise race the new startup and clear the loading UI.
        let generation = UUID()
        playbackGeneration = generation

        // Tear down any previous session first (mark so its stop doesn't cancel autoplay).
        userStopped = true
        progressTask?.cancel()
        controller?.stop()
        userStopped = false

        let playbackQueue = Self.normalizedQueue(queue, currentItem: item, startIndex: queueIndex)
        let playbackQueueIndex = 0
        let itemToPlay = playbackQueue[playbackQueueIndex]

        self.api = api
        self.config = config
        self.currentItem = itemToPlay
        self.queue = playbackQueue
        self.queueIndex = playbackQueueIndex
        self.onError = onError

        let c = PlaybackController(api: api, item: itemToPlay, config: config,
                                   startOverride: startOver ? 0 : nil,
                                   queue: playbackQueue, queueIndex: playbackQueueIndex,
                                   autoplayQueuedItems: autoplayNext)
        itemName = itemToPlay.name
        subtitle = Self.episodeSubtitle(itemToPlay)
        state = .starting
        isLaunching = true
        isQueueTransitioning = false
        positionSeconds = Ticks.toSeconds(itemToPlay.userData?.playbackPositionTicks)
        durationSeconds = Ticks.toSeconds(itemToPlay.runTimeTicks)
        artworkURL = api.playablePosterURL(for: itemToPlay, maxHeight: 160)
        let itemSource = itemToPlay.mediaSources?.first
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
                guard let self, self.playbackGeneration == generation else { return }
                if state == .starting && !self.isLaunching {
                    self.isQueueTransitioning = true
                }
                self.state = state
                self.positionSeconds = pos
                if state != .starting {
                    self.isLaunching = false
                    self.isQueueTransitioning = false
                }
                self.updateProgressClock(for: state)
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
        c.onItemChange = { [weak self] item, index, count in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                if self.currentItem?.id != item.id { self.isQueueTransitioning = true }
                self.currentItem = item
                self.queueIndex = index
                self.itemName = item.name
                self.subtitle = Self.episodeSubtitle(item)
                self.positionSeconds = Ticks.toSeconds(item.userData?.playbackPositionTicks)
                self.durationSeconds = Ticks.toSeconds(item.runTimeTicks)
                self.artworkURL = api.playablePosterURL(for: item, maxHeight: 160)
                self.isSeekable = self.durationSeconds > 0
                if self.queue.count != count, count > 0 {
                    self.queue = Array(self.queue.prefix(count))
                }
            }
        }
        c.onMediaInfoChange = { [weak self] duration, seekable in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                if duration > 0 { self.durationSeconds = duration }
                self.isSeekable = seekable
            }
        }
        c.onPlaybackStreams = { [weak self] streams, defaultAudio, defaultSubtitle in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
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
        c.onError = { [weak self] err in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                self.isLaunching = false
                onError(err.localizedDescription)
            }
        }
        c.onFinished = { [weak self] naturalEnd in
            Task { @MainActor in
                guard let self, self.playbackGeneration == generation else { return }
                self.isLaunching = false
                self.handleFinished(naturalEnd: naturalEnd)
            }
        }
        controller = c
        c.start()
    }

    func stop() {
        playbackGeneration = UUID()
        isLaunching = false
        isQueueTransitioning = false
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
    func setSubtitleDelay(_ seconds: Double) { controller?.setSubtitleDelay(seconds) }
    func setSubtitlePosition(_ percent: Int) { controller?.setSubtitlePosition(percent) }
    func setSubtitleScale(_ scale: Double) { controller?.setSubtitleScale(scale) }
    func playPrevious() {
        guard hasPreviousInQueue, !isQueueTransitioning else { return }
        if queueIndex > 0 { isQueueTransitioning = true }
        controller?.playPrevious()
    }
    func playNext() {
        guard hasNextInQueue, !isQueueTransitioning else { return }
        isQueueTransitioning = true
        controller?.playNext()
    }

    var hasPreviousInQueue: Bool { queueIndex > 0 || positionSeconds > 5 }
    var hasNextInQueue: Bool { queueIndex + 1 < queue.count }

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
            isQueueTransitioning = false
            queue = []
            queueIndex = 0
        }
    }

    private static func normalizedQueue(_ queue: [BaseItem], currentItem: BaseItem,
                                        startIndex: Int?) -> [BaseItem] {
        var seen = Set<String>()
        let unique = queue.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return [currentItem] }

        let start = startIndex.flatMap { unique.indices.contains($0) ? $0 : nil }
            ?? unique.firstIndex(where: { $0.id == currentItem.id })
        guard let start else { return [currentItem] }
        return Array(unique[start...])
    }

    static func episodeSubtitle(_ item: BaseItem) -> String? {
        guard item.type == "Episode" else { return nil }
        let s = item.parentIndexNumber.map { String(format: "S%02d", $0) } ?? ""
        let e = item.indexNumber.map { String(format: "E%02d", $0) } ?? ""
        return "\(item.seriesName ?? "") · \(s)\(e)".trimmingCharacters(in: .whitespaces)
    }
}
