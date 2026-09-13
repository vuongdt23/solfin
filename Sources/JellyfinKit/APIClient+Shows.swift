import Foundation

public extension APIClient {

    private static let episodeFields =
        "Overview,MediaSources,MediaStreams,RunTimeTicks,IndexNumber,ParentIndexNumber,SeriesId,SeasonId,ImageTags"

    /// Seasons of a series, ordered.
    func seasons(seriesId: String) async throws -> [BaseItem] {
        guard let uid = session?.userId else { throw JellyfinError.notAuthenticated }
        let q = [
            URLQueryItem(name: "userId", value: uid),
            URLQueryItem(name: "Fields", value: "ChildCount,ImageTags"),
        ]
        let req = try makeRequest(path: "Shows/\(seriesId)/Seasons", query: q)
        return try decode(ItemsResponse.self, from: try await send(req)).items
    }

    /// Episodes of a series. If `seasonId` is nil, returns all episodes across seasons in order.
    func episodes(seriesId: String, seasonId: String? = nil) async throws -> [BaseItem] {
        guard let uid = session?.userId else { throw JellyfinError.notAuthenticated }
        var q = [
            URLQueryItem(name: "userId", value: uid),
            URLQueryItem(name: "Fields", value: Self.episodeFields),
        ]
        if let seasonId { q.append(URLQueryItem(name: "seasonId", value: seasonId)) }
        let req = try makeRequest(path: "Shows/\(seriesId)/Episodes", query: q)
        return try decode(ItemsResponse.self, from: try await send(req)).items
    }

    /// The episode immediately following `episode` in its series' running order, if any.
    func nextEpisode(after episode: BaseItem) async throws -> BaseItem? {
        guard let seriesId = episode.seriesId else { return nil }
        let all = try await episodes(seriesId: seriesId)
        guard let idx = all.firstIndex(where: { $0.id == episode.id }),
              idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}
