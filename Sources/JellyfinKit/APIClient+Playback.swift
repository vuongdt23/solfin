import Foundation

/// The resolved decision to direct-play a specific media source.
public struct DirectPlayPlan: Sendable {
    public let itemId: String
    public let mediaSourceId: String
    public let playSessionId: String?
    public let streamURL: URL
    public var resumeSeconds: Double
}

public extension APIClient {

    /// Ask the server for media sources and resolve a direct-play plan for `item`.
    /// v1 does not negotiate transcoding: we require a direct-play/-stream source.
    func directPlayPlan(for item: BaseItem) async throws -> DirectPlayPlan {
        guard let uid = session?.userId else { throw JellyfinError.notAuthenticated }

        let payload: [String: Any] = [
            "UserId": uid,
            "MaxStreamingBitrate": 1_000_000_000,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": false,
            "AutoOpenLiveStream": true,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try makeRequest(path: "Items/\(item.id)/PlaybackInfo",
                                  method: "POST",
                                  query: [URLQueryItem(name: "userId", value: uid)],
                                  body: body)
        let info = try decode(PlaybackInfoResponse.self, from: try await send(req))

        // Prefer an explicit direct-play source, else direct-stream, else first.
        let source = info.mediaSources.first { $0.supportsDirectPlay == true }
            ?? info.mediaSources.first { $0.supportsDirectStream == true }
            ?? info.mediaSources.first
        guard let source,
              let url = directStreamURL(itemId: item.id, mediaSourceId: source.id,
                                        container: source.container) else {
            throw JellyfinError.noDirectPlaySource
        }

        return DirectPlayPlan(
            itemId: item.id,
            mediaSourceId: source.id,
            playSessionId: info.playSessionId,
            streamURL: url,
            resumeSeconds: Ticks.toSeconds(item.userData?.playbackPositionTicks)
        )
    }

    // MARK: - Playback state reporting

    private func report(path: String, _ payload: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let req = try makeRequest(path: path, method: "POST", body: body)
        try await send(req)
    }

    func reportPlaybackStart(_ plan: DirectPlayPlan) async throws {
        var p: [String: Any] = [
            "ItemId": plan.itemId,
            "MediaSourceId": plan.mediaSourceId,
            "PositionTicks": Ticks.fromSeconds(plan.resumeSeconds),
            "PlayMethod": "DirectPlay",
            "CanSeek": true,
            "IsPaused": false,
        ]
        if let psid = plan.playSessionId { p["PlaySessionId"] = psid }
        try await report(path: "Sessions/Playing", p)
    }

    func reportPlaybackProgress(_ plan: DirectPlayPlan, positionSeconds: Double,
                                isPaused: Bool) async throws {
        var p: [String: Any] = [
            "ItemId": plan.itemId,
            "MediaSourceId": plan.mediaSourceId,
            "PositionTicks": Ticks.fromSeconds(positionSeconds),
            "PlayMethod": "DirectPlay",
            "CanSeek": true,
            "IsPaused": isPaused,
            "EventName": "timeupdate",
        ]
        if let psid = plan.playSessionId { p["PlaySessionId"] = psid }
        try await report(path: "Sessions/Playing/Progress", p)
    }

    func reportPlaybackStopped(_ plan: DirectPlayPlan, positionSeconds: Double) async throws {
        var p: [String: Any] = [
            "ItemId": plan.itemId,
            "MediaSourceId": plan.mediaSourceId,
            "PositionTicks": Ticks.fromSeconds(positionSeconds),
        ]
        if let psid = plan.playSessionId { p["PlaySessionId"] = psid }
        try await report(path: "Sessions/Playing/Stopped", p)
    }
}
