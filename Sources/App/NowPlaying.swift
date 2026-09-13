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
    @AppStorage("solfin.autoplayNext") var autoplayNext: Bool = true

    private var controller: PlaybackController?

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
              startOver: Bool = false, onError: @escaping (String) -> Void) {
        // Tear down any previous session first (mark so its stop doesn't cancel autoplay).
        userStopped = true
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

        c.onStateChange = { [weak self] state, pos in
            Task { @MainActor in
                self?.state = state
                self?.positionSeconds = pos
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
        controller?.stop()
    }

    func togglePause() { controller?.togglePause() }

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
        if state == .stopped { itemName = nil; subtitle = nil }
    }

    static func episodeSubtitle(_ item: BaseItem) -> String? {
        guard item.type == "Episode" else { return nil }
        let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
        let e = item.indexNumber.map { "E\($0)" } ?? ""
        return "\(item.seriesName ?? "") · \(s)\(e)".trimmingCharacters(in: .whitespaces)
    }
}
