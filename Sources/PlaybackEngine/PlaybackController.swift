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

    private let queue = DispatchQueue(label: "dev.solfin.playback.controller")
    private var positionSeconds: Double = 0
    private var durationSeconds: Double = 0
    private var isPaused = false
    private var isSeekable = false
    private var didReportStopped = false
    private var naturalEnd = false
    private var state: State = .idle
    private var progressTimer: DispatchSourceTimer?

    private let timePosId = 1
    private let pauseId = 2
    private let durationId = 3
    private let seekableId = 4

    /// Delivered on the main queue: (state, positionSeconds).
    public var onStateChange: ((State, Double) -> Void)?
    /// Delivered on the main queue as mpv reports duration and seek capability.
    public var onMediaInfoChange: ((_ durationSeconds: Double, _ isSeekable: Bool) -> Void)?
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

        Task {
            do {
                var plan = try await api.directPlayPlan(for: item)
                if let startOverride { plan.resumeSeconds = startOverride }
                self.plan = plan

                // Launch mpv already pointed at the file with the resume position.
                try mpv.launch(binaryPath: binary, configDir: config.configDir,
                               additionalConfigPath: config.additionalConfigPath,
                               initialURL: plan.streamURL.absoluteString,
                               startSeconds: plan.resumeSeconds,
                               mediaTitle: Self.displayTitle(for: item))
                mpv.onExit = { [weak self] _ in self?.finalize() }

                self.queue.async {
                    self.positionSeconds = plan.resumeSeconds
                    self.isPaused = false
                    self.setState(.playing)
                    self.startProgressTimer()
                }
                connectIPC(resumeSeconds: plan.resumeSeconds)
                try? await api.reportPlaybackStart(plan)
            } catch {
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

    /// mpv stream selectors are 1-based track IDs. A nil subtitle disables subtitles.
    public func selectAudioTrack(id: Int) { ipc?.setProperty("aid", id) }
    public func selectVideoTrack(id: Int) { ipc?.setProperty("vid", id) }
    public func selectSubtitleTrack(id: Int?) {
        if let id { ipc?.setProperty("sid", id) }
        else { ipc?.setProperty("sid", "no") }
    }

    // MARK: - IPC

    private func connectIPC(resumeSeconds: Double) {
        let ipc = MPVIPC(socketPath: mpv.socketPath)
        ipc.onMessage = { [weak self] msg in self?.handle(msg) }
        ipc.onClose = { [weak self] in self?.finalize() }
        guard ipc.connect(timeout: 6) else {
            emitError(MPVProcess.LaunchError(message: "Could not connect to mpv IPC socket."))
            return
        }
        ipc.observeProperty("time-pos", id: timePosId)
        ipc.observeProperty("pause", id: pauseId)
        ipc.observeProperty("duration", id: durationId)
        ipc.observeProperty("seekable", id: seekableId)
        self.ipc = ipc
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
                        self.setState(self.isPaused ? .paused : .playing)
                    }
                case self.pauseId:
                    if let paused = Self.boolValue(msg["data"]) {
                        let changed = self.isPaused != paused
                        self.isPaused = paused
                        self.setState(paused ? .paused : .playing)
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
                default:
                    break
                }
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
    /// "Series · S1E2 · Episode Name"; everything else uses the item name.
    static func displayTitle(for item: BaseItem) -> String {
        if item.type == "Episode" {
            var parts: [String] = []
            if let series = item.seriesName { parts.append(series) }
            let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
            let e = item.indexNumber.map { "E\($0)" } ?? ""
            let se = s + e
            if !se.isEmpty { parts.append(se) }
            parts.append(item.name)
            return parts.joined(separator: " · ")
        }
        return item.name
    }
}
