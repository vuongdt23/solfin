import Foundation

public extension APIClient {

    private func requireUser() throws -> String {
        guard let uid = session?.userId else { throw JellyfinError.notAuthenticated }
        return uid
    }

    // Common set of fields we want back on items.
    private static let itemFields =
        "Overview,MediaSources,MediaStreams,ProductionYear,IndexNumber,ParentIndexNumber"

    /// Top-level libraries ("Views") for the signed-in user.
    func views() async throws -> [BaseItem] {
        let uid = try requireUser()
        let req = try makeRequest(path: "Users/\(uid)/Views")
        return try decode(ItemsResponse.self, from: try await send(req)).items
    }

    /// Children of a folder/library, paged.
    func items(parentId: String, startIndex: Int = 0, limit: Int = 100,
               sortBy: String = "SortName", includeItemTypes: String? = nil) async throws -> ItemsResponse {
        let uid = try requireUser()
        var q = [
            URLQueryItem(name: "ParentId", value: parentId),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "Fields", value: Self.itemFields),
            URLQueryItem(name: "Recursive", value: "false"),
        ]
        if let includeItemTypes {
            q.append(URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes))
            q.append(URLQueryItem(name: "Recursive", value: "true"))
        }
        let req = try makeRequest(path: "Users/\(uid)/Items", query: q)
        return try decode(ItemsResponse.self, from: try await send(req))
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
    func primaryImageURL(for item: BaseItem, maxHeight: Int = 480) -> URL? {
        guard let tag = item.imageTags?["Primary"] else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Items/\(item.id)/Images/Primary"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "fillHeight", value: String(maxHeight)),
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "quality", value: "90"),
        ]
        return comps?.url
    }

    /// Backdrop (wide) image URL for an item, if it has one.
    func backdropImageURL(for item: BaseItem, maxWidth: Int = 1280) -> URL? {
        guard let tag = item.backdropImageTags?.first else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Items/\(item.id)/Images/Backdrop/0"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "quality", value: "80"),
        ]
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
