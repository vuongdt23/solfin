import Foundation

/// A Jellyfin subtitle stream that mpv must load separately from the video file.
public struct ExternalSubtitle: Sendable, Hashable {
    public let streamIndex: Int
    public let url: URL
    public let title: String?
    public let language: String?
    public let isDefault: Bool
    public let isForced: Bool
}

/// The resolved decision to direct-play a specific media source.
public struct DirectPlayPlan: Sendable {
    public let itemId: String
    public let mediaSourceId: String
    public let playSessionId: String?
    public let streamURL: URL
    public let mediaStreams: [MediaStream]
    public let defaultAudioStreamIndex: Int?
    public let defaultSubtitleStreamIndex: Int?
    public let externalSubtitles: [ExternalSubtitle]
    public var resumeSeconds: Double

    public init(itemId: String, mediaSourceId: String, playSessionId: String?,
                streamURL: URL, resumeSeconds: Double,
                mediaStreams: [MediaStream] = [],
                defaultAudioStreamIndex: Int? = nil,
                defaultSubtitleStreamIndex: Int? = nil,
                externalSubtitles: [ExternalSubtitle] = []) {
        self.itemId = itemId
        self.mediaSourceId = mediaSourceId
        self.playSessionId = playSessionId
        self.streamURL = streamURL
        self.resumeSeconds = resumeSeconds
        self.mediaStreams = mediaStreams
        self.defaultAudioStreamIndex = defaultAudioStreamIndex
        self.defaultSubtitleStreamIndex = defaultSubtitleStreamIndex
        self.externalSubtitles = externalSubtitles
    }
}

public extension APIClient {

    /// Ask the server for media sources and resolve a direct-play plan for `item`.
    /// v1 does not negotiate transcoding: we require a direct-play/-stream source.
    func directPlayPlan(for item: BaseItem) async throws -> DirectPlayPlan {
        guard let uid = session?.userId else { throw JellyfinError.notAuthenticated }

        // A device profile is required for Jellyfin to populate DeliveryMethod and
        // DeliveryUrl. mpv can decode the original media and these subtitle formats,
        // so request direct play plus sidecar delivery rather than a video transcode.
        let textSubtitleFormats = [
            "srt", "subrip", "ass", "ssa", "webvtt", "vtt", "ttml", "smi",
            "microdvd", "sub",
        ]
        let bitmapSubtitleFormats = ["pgssub", "pgs", "dvdsub", "vobsub", "dvbsub"]
        let subtitleProfiles = textSubtitleFormats.flatMap { format in
            [
                ["Format": format, "Method": "Embed"],
                ["Format": format, "Method": "External"],
            ]
        } + bitmapSubtitleFormats.map { format in
            // Bitmap subtitles are reliable when they are already in the
            // direct-play file. Jellyfin's external bitmap endpoints are
            // format-sensitive and can produce unusable single-file VobSub/DVD
            // streams, so don't ask the server to extract them as sidecars.
            ["Format": format, "Method": "Embed"]
        }
        let payload: [String: Any] = [
            "UserId": uid,
            "MaxStreamingBitrate": 1_000_000_000,
            "EnableDirectPlay": true,
            "EnableDirectStream": true,
            "EnableTranscoding": false,
            "AutoOpenLiveStream": true,
            "DeviceProfile": [
                "Name": "Solfin mpv",
                // Empty codec/container restrictions mean "any" to Jellyfin.
                "DirectPlayProfiles": [["Type": "Video"], ["Type": "Audio"]],
                "TranscodingProfiles": [],
                "ContainerProfiles": [],
                "CodecProfiles": [],
                "SubtitleProfiles": subtitleProfiles,
            ],
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

        let streams = source.mediaStreams ?? []
        let externalSubtitles = streams.compactMap { stream -> ExternalSubtitle? in
            guard stream.type == "Subtitle",
                  Self.canLoadExternalSubtitle(stream),
                  (stream.deliveryMethod?.caseInsensitiveCompare("External") == .orderedSame
                   || stream.isExternal == true),
                  let index = stream.index,
                  let subtitleURL = subtitleURL(for: stream, itemId: item.id,
                                                mediaSourceId: source.id) else { return nil }
            return ExternalSubtitle(
                streamIndex: index,
                url: subtitleURL,
                title: stream.displayTitle,
                language: stream.language,
                isDefault: stream.isDefault == true,
                isForced: stream.isForced == true
            )
        }

        return DirectPlayPlan(
            itemId: item.id,
            mediaSourceId: source.id,
            playSessionId: info.playSessionId,
            streamURL: url,
            resumeSeconds: Ticks.toSeconds(item.userData?.playbackPositionTicks),
            mediaStreams: streams,
            defaultAudioStreamIndex: source.defaultAudioStreamIndex,
            defaultSubtitleStreamIndex: source.defaultSubtitleStreamIndex,
            externalSubtitles: externalSubtitles
        )
    }

    /// Resolve Jellyfin's DeliveryUrl. Same-server relative URLs need the access
    /// token because mpv fetches them outside URLSession; absolute third-party URLs
    /// must never receive our Jellyfin token.
    func subtitleURL(for stream: MediaStream, itemId: String,
                     mediaSourceId: String) -> URL? {
        let rawURL: URL?
        if let deliveryURL = stream.deliveryURL, !deliveryURL.isEmpty {
            if let absolute = URL(string: deliveryURL), absolute.scheme != nil {
                rawURL = absolute
            } else {
                let directoryBase = URL(string:
                    baseURL.absoluteString.hasSuffix("/")
                        ? baseURL.absoluteString
                        : baseURL.absoluteString + "/"
                )
                rawURL = directoryBase.flatMap {
                    URL(string: String(deliveryURL.drop(while: { $0 == "/" })),
                        relativeTo: $0)?.absoluteURL
                }
            }
        } else if (stream.isExternal == true
                   || stream.deliveryMethod?.caseInsensitiveCompare("External") == .orderedSame),
                  let index = stream.index {
            let format = Self.subtitleFormat(for: stream.codec)
            rawURL = baseURL.appendingPathComponent(
                "Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(index)/Stream.\(format)"
            )
        } else {
            rawURL = nil
        }

        guard let rawURL else { return nil }
        return authenticatedMediaURL(rawURL)
    }

    private func authenticatedMediaURL(_ url: URL) -> URL? {
        guard Self.sameOrigin(url, baseURL),
              let token = session?.accessToken, !token.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var query = components.queryItems ?? []
        if !query.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame
                                  || $0.name.caseInsensitiveCompare("ApiKey") == .orderedSame }) {
            query.append(URLQueryItem(name: "api_key", value: token))
        }
        components.queryItems = query
        return components.url
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ url: URL) -> Int? {
            url.port ?? (url.scheme?.lowercased() == "https" ? 443
                         : url.scheme?.lowercased() == "http" ? 80 : nil)
        }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && port(lhs) == port(rhs)
    }

    private static func canLoadExternalSubtitle(_ stream: MediaStream) -> Bool {
        switch stream.codec?.lowercased() {
        case "dvdsub", "vobsub":
            // mpv handles these when embedded in the direct-play file, but loading
            // them as a Jellyfin subtitle URL commonly yields an unusable single
            // bitmap stream without its required VobSub index/container metadata.
            return false
        default:
            return true
        }
    }

    private static func subtitleFormat(for codec: String?) -> String {
        switch codec?.lowercased() {
        case "subrip": return "srt"
        case "webvtt": return "vtt"
        case "pgs", "pgssub": return "sup"
        case "dvdsub", "vobsub": return "mks"
        case let codec?: return codec
        case nil: return "srt"
        }
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
