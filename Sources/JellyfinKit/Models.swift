import Foundation

// MARK: - Auth

public struct AuthenticationResult: Codable, Sendable {
    public let user: JFUser
    public let accessToken: String
    public let serverId: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

public struct JFUser: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

public struct PublicSystemInfo: Codable, Sendable {
    public let serverName: String
    public let version: String
    public let id: String

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case id = "Id"
    }
}

// MARK: - Items

public struct ItemsResponse: Codable, Sendable {
    public let items: [BaseItem]
    public let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

public struct BaseItem: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let type: String?               // "Movie", "Series", "Episode", "CollectionFolder", ...
    public let collectionType: String?     // for views: "movies", "tvshows", ...
    public let overview: String?
    public let productionYear: Int?
    public let runTimeTicks: Int64?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?
    public let seriesName: String?
    public let seriesId: String?
    public let seasonId: String?
    public let childCount: Int?
    public let imageTags: [String: String]?
    public let backdropImageTags: [String]?
    public let userData: UserItemData?
    public let mediaSources: [MediaSource]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case collectionType = "CollectionType"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case seriesName = "SeriesName"
        case seriesId = "SeriesId"
        case seasonId = "SeasonId"
        case childCount = "ChildCount"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case userData = "UserData"
        case mediaSources = "MediaSources"
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: BaseItem, rhs: BaseItem) -> Bool { lhs.id == rhs.id }
}

public struct UserItemData: Codable, Sendable, Hashable {
    public let playbackPositionTicks: Int64?
    public let playedPercentage: Double?
    public let played: Bool?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
        case played = "Played"
    }
}

// MARK: - Playback

public struct PlaybackInfoResponse: Codable, Sendable {
    public let mediaSources: [MediaSource]
    public let playSessionId: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
    }
}

public struct MediaSource: Codable, Sendable, Hashable {
    public let id: String
    public let name: String?
    public let container: String?
    public let supportsDirectPlay: Bool?
    public let supportsDirectStream: Bool?
    public let mediaStreams: [MediaStream]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case container = "Container"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case mediaStreams = "MediaStreams"
    }
}

public struct MediaStream: Codable, Sendable, Hashable {
    public let type: String?               // "Video", "Audio", "Subtitle"
    public let codec: String?
    public let displayTitle: String?
    public let language: String?
    public let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case codec = "Codec"
        case displayTitle = "DisplayTitle"
        case language = "Language"
        case isDefault = "IsDefault"
    }
}

// MARK: - Helpers

public enum Ticks {
    public static let perSecond: Int64 = 10_000_000

    public static func toSeconds(_ ticks: Int64?) -> Double {
        guard let ticks else { return 0 }
        return Double(ticks) / Double(perSecond)
    }

    public static func fromSeconds(_ seconds: Double) -> Int64 {
        Int64((seconds * Double(perSecond)).rounded())
    }
}
