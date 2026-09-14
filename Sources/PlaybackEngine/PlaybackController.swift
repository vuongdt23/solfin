import Foundation
import JellyfinKit

/// Orchestrates one playback: resolve direct-play plan → launch external mpv →
/// drive JSON IPC → keep Jellyfin's playback state in sync. Guarantees exactly one
/// `Sessions/Playing/Stopped` report on any terminal path.
public final class PlaybackController {

    public enum State: String, Sendable { case idle, starting, playing, paused, stopped }

    public struct Config {
        public var mpvBinaryPath: String?
        public var configDir: String?
        public var progressInterval: TimeInterval
        public var additionalConfigPath: String?
        public init(mpvBinaryPath: String? = nil, configDir: String? = nil,
                    progressInterval: TimeInterval = 10, additionalConfigPath: String? = nil) {
            self.mpvBinaryPath = mpvBinaryPath
            self.configDir = configDir
            self.progressInterval = progressInterval
            self.additionalConfigPath = additionalConfigPath
        }
    }

    private let api: APIClient
    private let item: BaseItem
    private let config: Config
    private let startOverride: Double?

    private let mpv = MPVProcess()
    private var ipc: MPVIPC?
    private var plan: DirectPlayPlan?

    /// UI selections use Jellyfin's source-wide MediaStream.Index. mpv assigns
    /// per-type IDs, and separately loaded subtitle files get new IDs at runtime.
    private var audioTrackIDs: [Int: Int] = [:]
    private var videoTrackIDs: [Int: Int] = [:]
    private var embeddedSubtitleTrackIDs: [Int: Int] = [:]
    private var externalSubtitleTrackIDs: [Int: Int] = [:]
    private var requestedAudioStreamIndex: Int?
    private var requestedVideoStreamIndex: Int?
    private var requestedSubtitleStreamIndex: Int?
    private var didRequestAudioSelection = false
    private var didRequestVideoSelection = false
    private var didRequestSubtitleSelection = false
    private var needsApplyAudioSelection = false
    private var needsApplyVideoSelection = false
    private var needsApplySubtitleSelection = false
    private var pendingExternalSubtitleURLs: [Int: String] = [:]
    private var loadingExternalSubtitleIndexes: Set<Int> = []

    private let queue = DispatchQueue(label: "dev.solfin.playback.controller")
    private var positionSeconds: Double = 0
    private var durationSeconds: Double = 0
    private var isPaused = false
    private var isSeekable = false
    private var didReportStopped = false
    private var naturalEnd = false
    private var state: State = .idle
    private var hasStartedPlayback = false
    private var progressTimer: DispatchSourceTimer?

    private let timePosId = 1
    private let pauseId = 2
    private let durationId = 3
    private let seekableId = 4
    private let trackListId = 5

    /// Delivered on the main queue: (state, positionSeconds).
    public var onStateChange: ((State, Double) -> Void)?
    /// Delivered on the main queue as mpv reports duration and seek capability.
    public var onMediaInfoChange: ((_ durationSeconds: Double, _ isSeekable: Bool) -> Void)?
    /// The selected PlaybackInfo source; unlike browse metadata this includes
    /// device-specific subtitle DeliveryUrl values.
    public var onPlaybackStreams: ((_ streams: [MediaStream],
                                    _ defaultAudioStreamIndex: Int?,
                                    _ defaultSubtitleStreamIndex: Int?) -> Void)?
    public var onError: ((Error) -> Void)?
    /// Delivered on the main queue when playback ends. `naturalEnd` is true only when
    /// mpv reported an "eof" end-file reason (the file played to completion) — the
    /// signal the app uses to decide whether to autoplay the next episode.
    public var onFinished: ((_ naturalEnd: Bool) -> Void)?

    /// `startOverride` forces a start position in seconds (e.g. 0 to "start over"),
    /// ignoring the item's saved resume point.
    public init(api: APIClient, item: BaseItem, config: Config, startOverride: Double? = nil) {
        self.api = api
        self.item = item
        self.config = config
        self.startOverride = startOverride
    }

    // MARK: - Lifecycle

    public func start() {
        guard let binary = MPVProcess.locateBinary(override: config.mpvBinaryPath) else {
            emitError(MPVProcess.LaunchError(message: "mpv not found. Install it (brew install mpv) or set its path in Settings."))
            return
        }
        setState(.starting)

        SolfinLog.info("Playback requested for item=\(item.id) title=\(Self.displayTitle(for: item))", category: .playback)

        Task {
            do {
                let directPlanStarted = Date()
                var plan = try await api.directPlayPlan(for: item)
                SolfinLog.info("directPlayPlan resolved in \(Int(Date().timeIntervalSince(directPlanStarted) * 1000))ms stream=\(SolfinLog.redactedURL(plan.streamURL))", category: .playback)
                if let startOverride { plan.resumeSeconds = startOverride }
                self.plan = plan
                self.prepareTrackMaps(for: plan)
                DispatchQueue.main.async {
                    self.onPlaybackStreams?(plan.mediaStreams,
                                            plan.defaultAudioStreamIndex,
                                            plan.defaultSubtitleStreamIndex)
                }

                // Prefer the prewarmed on-disk logo. On the first cold route we allow a
                // blocking download so the OSC still gets the logo; subsequent plays are
                // cache hits and do not slow launch.
                let logoStarted = Date()
                let logoOverlay = await LogoOverlayCache.shared.overlay(for: item, api: api,
                                                                        downloadIfNeeded: true)
                SolfinLog.info("logo overlay \(logoOverlay == nil ? "unavailable" : "ready") in \(Int(Date().timeIntervalSince(logoStarted) * 1000))ms", category: .cache)

                let title = Self.displayTitle(for: item)
                let mpvLogPath = SolfinLog.makeMPVLogPath(title: title)
                let launchStarted = Date()
                try mpv.launch(binaryPath: binary, configDir: config.configDir,
                               additionalConfigPath: config.additionalConfigPath,
                               initialURL: plan.streamURL.absoluteString,
                               startSeconds: plan.resumeSeconds,
                               mediaTitle: title,
                               logoOverlay: logoOverlay,
                               mpvLogPath: mpvLogPath,
                               mpvMessageLevel: SolfinLog.currentLevel.mpvMessageLevel)
                SolfinLog.info("mpv Process.run returned in \(Int(Date().timeIntervalSince(launchStarted) * 1000))ms log=\(mpvLogPath ?? "off")", category: .mpv)
                mpv.onExit = { [weak self] _ in self?.finalize() }

                self.queue.async {
                    self.positionSeconds = plan.resumeSeconds
                    self.isPaused = false
                    // Keep the UI in `.starting` until mpv tells us the file is really
                    // loaded / playback properties arrive. Process.run only means the
                    // mpv process was spawned, not that the window is visible or media is ready.
                    self.startProgressTimer()
                }
                connectIPC(resumeSeconds: plan.resumeSeconds)
                try? await api.reportPlaybackStart(plan)
            } catch {
                SolfinLog.error("Playback startup failed: \(error.localizedDescription)", category: .playback)
                emitError(error)
                finalize()
            }
        }
    }

    /// Ask mpv to quit; finalize() runs from the process exit / socket close.
    public func stop() {
        ipc?.quit()
        mpv.terminate()
    }

    public func setPaused(_ paused: Bool) {
        queue.async { self.setPausedLocked(paused) }
    }

    public func togglePause() {
        queue.async { self.setPausedLocked(!self.isPaused) }
    }

    /// Must be called on `queue`. Update optimistically; mpv's observed `pause`
    /// property remains authoritative and will reconcile the state.
    private func setPausedLocked(_ paused: Bool) {
        guard !didReportStopped else { return }
        isPaused = paused
        ipc?.setProperty("pause", paused)
        setState(paused ? .paused : .playing)
        reportProgressNow()
    }

    public func seek(relativeSeconds: Double) {
        ipc?.command(["seek", relativeSeconds, "relative+exact"])
    }

    public func seek(to seconds: Double) {
        ipc?.command(["seek", max(0, seconds), "absolute+exact"])
    }

    /// Track selectors take Jellyfin's `MediaStream.Index`, not mpv's unrelated ID.
    public func selectAudioTrack(id: Int) {
        queue.async {
            self.didRequestAudioSelection = true
            self.requestedAudioStreamIndex = id
            self.needsApplyAudioSelection = true
            self.applyRequestedAudioSelection()
        }
    }

    public func selectVideoTrack(id: Int) {
        queue.async {
            self.didRequestVideoSelection = true
            self.requestedVideoStreamIndex = id
            self.needsApplyVideoSelection = true
            self.applyRequestedVideoSelection()
        }
    }

    public func selectSubtitleTrack(id: Int?) {
        queue.async {
            self.didRequestSubtitleSelection = true
            self.requestedSubtitleStreamIndex = id
            self.needsApplySubtitleSelection = true
            self.applyRequestedSubtitleSelection()
        }
    }

    // MARK: - IPC

    private func connectIPC(resumeSeconds: Double) {
        let ipc = MPVIPC(socketPath: mpv.socketPath)
        ipc.onMessage = { [weak self] msg in self?.handle(msg) }
        ipc.onClose = { [weak self] in self?.finalize() }
        let connectStarted = Date()
        guard ipc.connect(timeout: 6) else {
            SolfinLog.error("Could not connect to mpv IPC socket after 6s", category: .mpv)
            emitError(MPVProcess.LaunchError(message: "Could not connect to mpv IPC socket."))
            return
        }
        SolfinLog.info("mpv IPC connected in \(Int(Date().timeIntervalSince(connectStarted) * 1000))ms", category: .mpv)
        ipc.observeProperty("time-pos", id: timePosId)
        ipc.observeProperty("pause", id: pauseId)
        ipc.observeProperty("duration", id: durationId)
        ipc.observeProperty("seekable", id: seekableId)
        ipc.observeProperty("track-list", id: trackListId)
        self.ipc = ipc

        queue.async {
            if !self.didRequestAudioSelection {
                self.requestedAudioStreamIndex = self.plan?.defaultAudioStreamIndex
                self.needsApplyAudioSelection = self.requestedAudioStreamIndex != nil
            }
            if !self.didRequestVideoSelection {
                self.needsApplyVideoSelection = self.requestedVideoStreamIndex != nil
            }
            if !self.didRequestSubtitleSelection {
                self.requestedSubtitleStreamIndex = self.plan?.defaultSubtitleStreamIndex
                // Apply once even when the server default is nil so mpv does not
                // auto-select a subtitle behind the app's back.
                self.needsApplySubtitleSelection = true
            }
            self.applyRequestedAudioSelection()
            self.applyRequestedVideoSelection()
            self.applyRequestedSubtitleSelection()

            // Sidecars are separate HTTP resources, so explicitly add every one to
            // mpv. "auto" keeps the current/default subtitle selection unchanged.
            for subtitle in self.plan?.externalSubtitles ?? [] {
                self.loadExternalSubtitle(streamIndex: subtitle.streamIndex)
            }
        }
    }

    private func handle(_ msg: [String: Any]) {
        queue.async {
            guard let event = msg["event"] as? String else { return }
            switch event {
            case "property-change":
                guard let id = Self.intValue(msg["id"]) else { return }
                switch id {
                case self.timePosId:
                    if let pos = Self.doubleValue(msg["data"]) {
                        self.positionSeconds = pos
                        // time-pos can arrive before the first frame is displayed. Keep
                        // the UI in the launch state until mpv's playback-restart event,
                        // which is emitted after the post-seek playback pipeline resumes.
                        if self.hasStartedPlayback {
                            self.setState(self.isPaused ? .paused : .playing)
                        }
                    }
                case self.pauseId:
                    if let paused = Self.boolValue(msg["data"]) {
                        let changed = self.isPaused != paused
                        self.isPaused = paused
                        if self.hasStartedPlayback {
                            self.setState(paused ? .paused : .playing)
                        }
                        if changed { self.reportProgressNow() }
                    }
                case self.durationId:
                    if let duration = Self.doubleValue(msg["data"]) {
                        self.durationSeconds = duration
                        self.emitMediaInfo()
                    }
                case self.seekableId:
                    if let seekable = Self.boolValue(msg["data"]) {
                        self.isSeekable = seekable
                        self.emitMediaInfo()
                    }
                case self.trackListId:
                    self.updateExternalSubtitleTracks(from: msg["data"])
                default:
                    break
                }
            case "file-loaded":
                SolfinLog.debug("mpv file-loaded; waiting for playback-restart/first frame", category: .mpv)
            case "playback-restart":
                if !self.hasStartedPlayback {
                    SolfinLog.info("mpv playback became ready via playback-restart", category: .mpv)
                }
                self.hasStartedPlayback = true
                self.setState(self.isPaused ? .paused : .playing)
            case "end-file":
                // reason: "eof" (completed) | "stop" | "quit" | "error" | "redirect"
                if (msg["reason"] as? String) == "eof" { self.naturalEnd = true }
                self.finalizeLocked()
            case "shutdown":
                self.finalizeLocked()
            default:
                break
            }
        }
    }

    // MARK: - Track mapping

    /// Jellyfin indexes every stream in one source-wide sequence. mpv IDs are
    /// 1-based within each media type and omit sidecars from the main file.
    private func prepareTrackMaps(for plan: DirectPlayPlan) {
        audioTrackIDs.removeAll()
        videoTrackIDs.removeAll()
        embeddedSubtitleTrackIDs.removeAll()
        externalSubtitleTrackIDs.removeAll()
        pendingExternalSubtitleURLs.removeAll()
        loadingExternalSubtitleIndexes.removeAll()
        hasStartedPlayback = false
        requestedAudioStreamIndex = nil
        requestedVideoStreamIndex = nil
        requestedSubtitleStreamIndex = nil
        didRequestAudioSelection = false
        didRequestVideoSelection = false
        didRequestSubtitleSelection = false
        needsApplyAudioSelection = false
        needsApplyVideoSelection = false
        needsApplySubtitleSelection = false

        var audioID = 1
        var videoID = 1
        var subtitleID = 1
        for stream in plan.mediaStreams {
            guard let index = stream.index else { continue }
            switch stream.type {
            case "Audio" where stream.isExternal != true:
                audioTrackIDs[index] = audioID
                audioID += 1
            case "Video" where stream.isExternal != true:
                videoTrackIDs[index] = videoID
                videoID += 1
            case "Subtitle" where stream.isExternal != true:
                embeddedSubtitleTrackIDs[index] = subtitleID
                subtitleID += 1
            default:
                break
            }
        }
        for subtitle in plan.externalSubtitles {
            pendingExternalSubtitleURLs[subtitle.streamIndex] = subtitle.url.absoluteString
        }
    }

    private func applyRequestedAudioSelection() {
        guard needsApplyAudioSelection,
              let ipc,
              let requestedAudioStreamIndex,
              let mpvID = audioTrackIDs[requestedAudioStreamIndex] else { return }
        ipc.setProperty("aid", mpvID)
        needsApplyAudioSelection = false
    }

    private func applyRequestedVideoSelection() {
        guard needsApplyVideoSelection,
              let ipc,
              let requestedVideoStreamIndex,
              let mpvID = videoTrackIDs[requestedVideoStreamIndex] else { return }
        ipc.setProperty("vid", mpvID)
        needsApplyVideoSelection = false
    }

    private func applyRequestedSubtitleSelection() {
        guard needsApplySubtitleSelection, let ipc else { return }
        guard let id = requestedSubtitleStreamIndex else {
            ipc.setProperty("sid", "no")
            needsApplySubtitleSelection = false
            return
        }
        if let mpvID = embeddedSubtitleTrackIDs[id]
            ?? externalSubtitleTrackIDs[id] {
            ipc.setProperty("sid", mpvID)
            needsApplySubtitleSelection = false
            return
        }
        loadExternalSubtitle(streamIndex: id)
    }

    /// Load one external subtitle on demand. `sub-add auto` does not disturb the
    /// current selection; the track-list observer discovers mpv's new ID.
    private func loadExternalSubtitle(streamIndex: Int) {
        guard externalSubtitleTrackIDs[streamIndex] == nil,
              !loadingExternalSubtitleIndexes.contains(streamIndex),
              let subtitle = plan?.externalSubtitles.first(where: {
                  $0.streamIndex == streamIndex
              }) else { return }
        loadingExternalSubtitleIndexes.insert(streamIndex)
        ipc?.addSubtitle(url: subtitle.url.absoluteString,
                         title: subtitle.title, language: subtitle.language)
    }

    private func updateExternalSubtitleTracks(from value: Any?) {
        guard let tracks = value as? [[String: Any]] else { return }
        for track in tracks where track["type"] as? String == "sub" {
            guard Self.boolValue(track["external"]) == true,
                  let filename = track["external-filename"] as? String,
                  let mpvID = Self.intValue(track["id"]),
                  let streamIndex = pendingExternalSubtitleURLs.first(where: {
                      $0.value == filename
                  })?.key else { continue }
            externalSubtitleTrackIDs[streamIndex] = mpvID
            loadingExternalSubtitleIndexes.remove(streamIndex)
        }
        if needsApplySubtitleSelection {
            applyRequestedSubtitleSelection()
        }
    }

    // MARK: - Progress reporting

    private func startProgressTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + config.progressInterval, repeating: config.progressInterval)
        timer.setEventHandler { [weak self] in self?.reportProgressNow() }
        timer.resume()
        progressTimer = timer
    }

    /// Must be called on `queue`.
    private func reportProgressNow() {
        guard let plan, !didReportStopped else { return }
        let pos = positionSeconds
        let paused = isPaused
        Task { try? await api.reportPlaybackProgress(plan, positionSeconds: pos, isPaused: paused) }
    }

    // MARK: - Termination (exactly once)

    private func finalize() {
        queue.async { self.finalizeLocked() }
    }

    /// Must be called on `queue`.
    private func finalizeLocked() {
        guard !didReportStopped else { return }
        didReportStopped = true

        progressTimer?.cancel()
        progressTimer = nil

        let pos = positionSeconds
        if let plan {
            Task { try? await api.reportPlaybackStopped(plan, positionSeconds: pos) }
        }
        ipc?.disconnect()
        mpv.cleanupSocket()
        setState(.stopped)

        let natural = naturalEnd
        DispatchQueue.main.async { self.onFinished?(natural) }
    }

    // MARK: - State plumbing

    private func setState(_ s: State) {
        state = s
        let pos = positionSeconds
        DispatchQueue.main.async { self.onStateChange?(s, pos) }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private func emitMediaInfo() {
        let duration = durationSeconds
        let seekable = isSeekable
        DispatchQueue.main.async { self.onMediaInfoChange?(duration, seekable) }
    }

    private func emitError(_ error: Error) {
        DispatchQueue.main.async { self.onError?(error) }
    }

    /// The human title shown in the mpv OSC. Episodes read as
    /// "Series · S01E02 · Episode Name"; everything else uses the item name.
    static func displayTitle(for item: BaseItem) -> String {
        if item.type == "Episode" {
            var parts: [String] = []
            if let series = item.seriesName { parts.append(series) }
            let se = episodeCode(for: item)
            if !se.isEmpty { parts.append(se) }
            parts.append(item.name)
            return parts.joined(separator: " · ")
        }
        return item.name
    }

    private static func episodeCode(for item: BaseItem) -> String {
        let s = item.parentIndexNumber.map { String(format: "S%02d", $0) } ?? ""
        let e = item.indexNumber.map { String(format: "E%02d", $0) } ?? ""
        return s + e
    }
}
