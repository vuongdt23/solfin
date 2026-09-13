import Foundation

public extension APIClient {

    private func requireUser() throws -> String {
        guard let uid = session?.userId else { throw JellyfinError.notAuthenticated }
        return uid
    }

    // Common set of fields we want back on items.
    private static let itemFields =
        "Overview,MediaSources,MediaStreams,ProductionYear,IndexNumber,ParentIndexNumber,DateCreated,OfficialRating,CommunityRating,Genres,ParentBackdropItemId,ParentBackdropImageTags,SeriesPrimaryImageTag"

    /// Top-level libraries ("Views") for the signed-in user.
    func views() async throws -> [BaseItem] {
        let uid = try requireUser()
        let req = try makeRequest(path: "Users/\(uid)/Views")
        return try decode(ItemsResponse.self, from: try await send(req)).items
    }

    /// Children of a folder/library, paged.
    func items(parentId: String, startIndex: Int = 0, limit: Int = 100,
               sortBy: String = "SortName", sortOrder: String = "Ascending",
               includeItemTypes: String? = nil, recursive: Bool = false,
               filters: String? = nil) async throws -> ItemsResponse {
        let uid = try requireUser()
        var q = [
            URLQueryItem(name: "ParentId", value: parentId),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: sortOrder),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "Recursive", value: recursive || includeItemTypes != nil ? "true" : "false"),
            URLQueryItem(name: "EnableUserData", value: "true"),
        ]
        if let includeItemTypes {
            q.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes))
        }
        if let filters { q.append(URLQueryItem(name: "Filters", value: filters)) }
        let req = try makeRequest(path: "Users/\(uid)/Items", query: q)
        return try decode(ItemsResponse.self, from: try await send(req))
    }

    /// Fetch a specific set of items. The server may not preserve `ids` order, so callers
    /// that care about ordering should reorder the returned items themselves.
    func items(ids: [String], includeItemTypes: String? = nil) async throws -> ItemsResponse {
        guard !ids.isEmpty else { return ItemsResponse(items: [], totalRecordCount: 0) }
        let uid = try requireUser()
        var q = [
            URLQueryItem(name: "Ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "Limit", value: String(ids.count)),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
        ]
        if let includeItemTypes {
            q.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes))
        }
        let req = try makeRequest(path: "Users/\(uid)/Items", query: q)
        return try decode(ItemsResponse.self, from: try await send(req))
    }

    /// Artwork-rich, unplayed titles for the home feature carousel.
    func featuredItems(limit: Int = 20) async throws -> [BaseItem] {
        let uid = try requireUser()
        let q = [
            URLQueryItem(name: "UserId", value: uid),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series"),
            URLQueryItem(name: "SortBy", value: "Random"),
            URLQueryItem(name: "Filters", value: "IsUnplayed"),
            URLQueryItem(name: "HasOverview", value: "true"),
            URLQueryItem(name: "ImageTypes", value: "Logo,Backdrop"),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.itemFields),
        ]
        let req = try makeRequest(path: "Users/\(uid)/Items", query: q)
        return try decode(ItemsResponse.self, from: try await send(req)).items
    }

    /// Recently added videos across all visible libraries.
    func latestItems(limit: Int = 20, parentId: String? = nil,
                     includeItemTypes: String = "Movie,Series") async throws -> [BaseItem] {
        let uid = try requireUser()
        var q = [
            URLQueryItem(name: "UserId", value: uid),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes),
            URLQueryItem(name: "EnableImages", value: "true"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
        ]
        if let parentId { q.append(URLQueryItem(name: "ParentId", value: parentId)) }
        let req = try makeRequest(path: "Users/\(uid)/Items/Latest", query: q)
        return try decode([BaseItem].self, from: try await send(req))
    }

    /// Search the user's video libraries by title.
    func searchItems(term: String, includeItemTypes: String? = nil,
                     startIndex: Int = 0, limit: Int = 60) async throws -> ItemsResponse {
        let uid = try requireUser()
        var q = [
            URLQueryItem(name: "SearchTerm", value: term),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "MediaTypes", value: "Video"),
            URLQueryItem(name: "SortBy", value: "SortName"),
        ]
        if let includeItemTypes {
            q.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes))
        }
        let req = try makeRequest(path: "Users/\(uid)/Items", query: q)
        return try decode(ItemsResponse.self, from: try await send(req))
    }

    /// Recently added episodes, useful for following currently-updating series.
    func latestEpisodes(limit: Int = 20) async throws -> [BaseItem] {
        try await latestItems(limit: limit, includeItemTypes: "Episode")
    }

    /// Series ordered by recently-added episode activity. This keeps TV libraries as a
    /// series grid while still surfacing shows with fresh episodes first. Series without
    /// a scanned recent episode are still included and sorted alphabetically after active series.
    func recentlyActiveSeries(parentId: String, limit: Int? = nil, sortOrder: String = "Descending",
                              filters: String? = nil, episodeScanLimit: Int = 1_000,
                              allSeriesLimit: Int = 5_000) async throws -> [BaseItem] {
        async let seriesResponse = items(parentId: parentId,
                                         startIndex: 0,
                                         limit: allSeriesLimit,
                                         sortBy: "SortName",
                                         sortOrder: "Ascending",
                                         includeItemTypes: "Series",
                                         recursive: true,
                                         filters: filters)
        async let episodeResponse = items(parentId: parentId,
                                          startIndex: 0,
                                          limit: episodeScanLimit,
                                          sortBy: "DateCreated",
                                          sortOrder: "Descending",
                                          includeItemTypes: "Episode",
                                          recursive: true,
                                          filters: filters)

        var latestEpisodeDateBySeriesId: [String: String] = [:]
        for episode in try await episodeResponse.items {
            guard let seriesId = episode.seriesId, let dateCreated = episode.dateCreated else { continue }
            if latestEpisodeDateBySeriesId[seriesId] == nil { latestEpisodeDateBySeriesId[seriesId] = dateCreated }
        }

        let ordered = try await seriesResponse.items.sorted { lhs, rhs in
            let lhsDate = latestEpisodeDateBySeriesId[lhs.id]
            let rhsDate = latestEpisodeDateBySeriesId[rhs.id]
            switch (lhsDate, rhsDate) {
            case let (l?, r?) where l != r:
                return sortOrder == "Ascending" ? l < r : l > r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        if let limit { return Array(ordered.prefix(limit)) }
        return ordered
    }

    /// Continue Watching.
    func resumeItems(limit: Int = 20) async throws -> [BaseItem] {
        let uid = try requireUser()
        let q = [
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "MediaTypes", value: "Video"),
        ]
        let req = try makeRequest(path: "Users/\(uid)/Items/Resume", query: q)
        return try decode(ItemsResponse.self, from: try await send(req)).items
    }

    /// Next Up (episodes).
    func nextUp(limit: Int = 20) async throws -> [BaseItem] {
        let uid = try requireUser()
        let q = [
            URLQueryItem(name: "UserId", value: uid),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "Fields", value: Self.itemFields),
        ]
        let req = try makeRequest(path: "Shows/NextUp", query: q)
        return try decode(ItemsResponse.self, from: try await send(req)).items
    }

    /// Full detail for a single item (includes UserData with resume position).
    func item(id: String) async throws -> BaseItem {
        let uid = try requireUser()
        let q = [URLQueryItem(name: "Fields", value: Self.itemFields)]
        let req = try makeRequest(path: "Users/\(uid)/Items/\(id)", query: q)
        return try decode(BaseItem.self, from: try await send(req))
    }

    // MARK: - Image / stream URLs

    /// Primary image URL for an item (nil if it has no primary image tag).
    func primaryImageURL(for item: BaseItem, maxHeight: Int? = 720, quality: Int = 96) -> URL? {
        guard let tag = item.imageTags?["Primary"] else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Items/\(item.id)/Images/Primary"),
                                  resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "tag", value: tag),
                     URLQueryItem(name: "quality", value: String(quality))]
        if let maxHeight { query.append(URLQueryItem(name: "maxHeight", value: String(maxHeight))) }
        comps?.queryItems = query
        return comps?.url
    }

    /// Transparent title treatment used by featured media when Jellyfin has one.
    func logoImageURL(for item: BaseItem, maxWidth: Int? = 1000) -> URL? {
        guard let tag = item.imageTags?["Logo"] else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Items/\(item.id)/Images/Logo"),
                                  resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "tag", value: tag),
                     URLQueryItem(name: "quality", value: "100")]
        if let maxWidth { query.append(URLQueryItem(name: "maxWidth", value: String(maxWidth))) }
        comps?.queryItems = query
        return comps?.url
    }

    /// Backdrop image. Pass nil to request the server's original resolution.
    func backdropImageURL(for item: BaseItem, maxWidth: Int? = 1920) -> URL? {
        guard let tag = item.backdropImageTags?.first else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Items/\(item.id)/Images/Backdrop/0"),
                                  resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "tag", value: tag),
                     URLQueryItem(name: "quality", value: "100")]
        if let maxWidth { query.append(URLQueryItem(name: "maxWidth", value: String(maxWidth))) }
        comps?.queryItems = query
        return comps?.url
    }

    /// Poster artwork for a playable item. Pass nil for original resolution.
    /// Episodes use their series poster when present.
    func playablePosterURL(for item: BaseItem, maxHeight: Int? = 1200) -> URL? {
        guard item.type == "Episode", let seriesId = item.seriesId,
              let tag = item.seriesPrimaryImageTag else {
            return primaryImageURL(for: item, maxHeight: maxHeight, quality: 100)
        }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Items/\(seriesId)/Images/Primary"),
                                  resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "tag", value: tag),
                     URLQueryItem(name: "quality", value: "100")]
        if let maxHeight { query.append(URLQueryItem(name: "maxHeight", value: String(maxHeight))) }
        comps?.queryItems = query
        return comps?.url
    }

    /// Episode backdrop, falling back to its series backdrop. Pass nil for original resolution.
    func episodeBackdropURL(for item: BaseItem, maxWidth: Int? = 2400) -> URL? {
        if let own = backdropImageURL(for: item, maxWidth: maxWidth) { return own }
        guard let parentId = item.parentBackdropItemId,
              let tag = item.parentBackdropImageTags?.first else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Items/\(parentId)/Images/Backdrop/0"),
                                  resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "tag", value: tag),
                     URLQueryItem(name: "quality", value: "100")]
        if let maxWidth { query.append(URLQueryItem(name: "maxWidth", value: String(maxWidth))) }
        comps?.queryItems = query
        return comps?.url
    }

    /// Direct static-file stream URL (raw file, no transcode). Token in query so mpv can fetch it.
    func directStreamURL(itemId: String, mediaSourceId: String, container: String?) -> URL? {
        // Jellyfin may report a comma-separated ffmpeg container list (e.g.
        // "mov,mp4,m4a,3gp,3g2,mj2"); use only the first token as the URL extension.
        let firstContainer = container?.split(separator: ",").first.map(String.init)
        let ext = firstContainer.map { ".\($0)" } ?? ""
        var comps = URLComponents(url: baseURL.appendingPathComponent("Videos/\(itemId)/stream\(ext)"),
                                  resolvingAgainstBaseURL: false)
        var q = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
        ]
        if let token = session?.accessToken { q.append(URLQueryItem(name: "api_key", value: token)) }
        comps?.queryItems = q
        return comps?.url
    }
}
