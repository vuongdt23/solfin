import Foundation

public extension APIClient {

    private static let episodeFields =
        "Overview,MediaSources,MediaStreams,RunTimeTicks,IndexNumber,ParentIndexNumber,SeriesId,SeasonId,ImageTags,ParentBackdropItemId,ParentBackdropImageTags,ParentLogoItemId,ParentLogoImageTag,SeriesPrimaryImageTag,ProductionYear,OfficialRating,CommunityRating,Genres"

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

    /// Episodes immediately before and after `episode` in series running order.
    func adjacentEpisodes(to episode: BaseItem) async throws -> (previous: BaseItem?, next: BaseItem?) {
        guard let seriesId = episode.seriesId else { return (nil, nil) }
        let all = try await episodes(seriesId: seriesId)
        guard let index = all.firstIndex(where: { $0.id == episode.id }) else { return (nil, nil) }
        let previous = index > 0 ? all[index - 1] : nil
        let next = index + 1 < all.count ? all[index + 1] : nil
        return (previous, next)
    }

    /// The episode immediately following `episode` in its series' running order, if any.
    func nextEpisode(after episode: BaseItem) async throws -> BaseItem? {
        try await adjacentEpisodes(to: episode).next
    }
}
