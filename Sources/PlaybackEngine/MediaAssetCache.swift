import AppKit
import Foundation
import JellyfinKit
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Shared disk cache for original Jellyfin images and derived mpv BGRA overlays.
public actor MediaAssetCache {
    public static let shared = MediaAssetCache()

    public struct Statistics: Sendable {
        public let assetCount: Int
        public let variantCount: Int
        public let sourceBytes: Int64
        public let variantBytes: Int64
        public let location: String
        public init(assetCount: Int, variantCount: Int, sourceBytes: Int64, variantBytes: Int64, location: String) {
            self.assetCount = assetCount; self.variantCount = variantCount; self.sourceBytes = sourceBytes; self.variantBytes = variantBytes; self.location = location
        }
        public var totalBytes: Int64 { sourceBytes + variantBytes }
    }

    private let directory: URL
    private let databaseURL: URL
    private var database: OpaquePointer?
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var imageMemory: [String: NSImage] = [:]
    private let overlayVersion = 1

    public init(directory: URL? = nil) {
        if let directory { self.directory = directory }
        else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.directory = base.appendingPathComponent("Solfin/MediaAssets", isDirectory: true)
        }
        self.databaseURL = self.directory.appendingPathComponent("catalog.sqlite")
        self.database = nil
    }

    deinit { if let database { sqlite3_close(database) } }

    private func openDatabase() {
        guard database == nil else { return }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return }
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else { return }
        _ = sqlite3_exec(database, "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS assets (key TEXT PRIMARY KEY, url TEXT NOT NULL, bytes INTEGER NOT NULL, mime TEXT, width INTEGER, height INTEGER, created REAL NOT NULL, accessed REAL NOT NULL); CREATE TABLE IF NOT EXISTS variants (asset_key TEXT NOT NULL, variant TEXT NOT NULL, path TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, bytes INTEGER NOT NULL, conversion_version INTEGER NOT NULL, accessed REAL NOT NULL, PRIMARY KEY(asset_key, variant));", nil, nil, nil)
    }

    private func recordSource(key: String, url: URL, bytes: Int, mime: String?, width: Int?, height: Int?) {
        openDatabase(); guard let database else { return }
        let sql = "INSERT INTO assets(key,url,bytes,mime,width,height,created,accessed) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(key) DO UPDATE SET bytes=excluded.bytes,mime=excluded.mime,width=excluded.width,height=excluded.height,accessed=excluded.accessed;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient); sqlite3_bind_text(statement, 2, Self.identity(for: url), -1, sqliteTransient)
        sqlite3_bind_int64(statement, 3, Int64(bytes)); if let mime { sqlite3_bind_text(statement, 4, mime, -1, sqliteTransient) } else { sqlite3_bind_null(statement, 4) }
        if let width { sqlite3_bind_int(statement, 5, Int32(width)) } else { sqlite3_bind_null(statement, 5) }; if let height { sqlite3_bind_int(statement, 6, Int32(height)) } else { sqlite3_bind_null(statement, 6) }
        let now = Date().timeIntervalSince1970; sqlite3_bind_double(statement, 7, now); sqlite3_bind_double(statement, 8, now); _ = sqlite3_step(statement)
    }

    private func recordVariant(key: String, variant: String, path: URL, width: Int, height: Int, bytes: Int) {
        openDatabase(); guard let database else { return }
        let sql = "INSERT OR REPLACE INTO variants(asset_key,variant,path,width,height,bytes,conversion_version,accessed) VALUES(?,?,?,?,?,?,?,?);"
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }; defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient); sqlite3_bind_text(statement, 2, variant, -1, sqliteTransient); sqlite3_bind_text(statement, 3, path.path, -1, sqliteTransient)
        sqlite3_bind_int(statement, 4, Int32(width)); sqlite3_bind_int(statement, 5, Int32(height)); sqlite3_bind_int64(statement, 6, Int64(bytes)); sqlite3_bind_int(statement, 7, Int32(overlayVersion)); sqlite3_bind_double(statement, 8, Date().timeIntervalSince1970); _ = sqlite3_step(statement)
    }

    public func statistics() -> Statistics {
        openDatabase()
        guard let database else { return Statistics(assetCount: 0, variantCount: 0, sourceBytes: 0, variantBytes: 0, location: directory.path) }
        func value(_ sql: String) -> Int64 {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return sqlite3_column_int64(statement, 0)
        }
        return Statistics(assetCount: Int(value("SELECT COUNT(*) FROM assets")), variantCount: Int(value("SELECT COUNT(*) FROM variants")), sourceBytes: value("SELECT COALESCE(SUM(bytes),0) FROM assets"), variantBytes: value("SELECT COALESCE(SUM(bytes),0) FROM variants"), location: directory.path)
    }

    public func clear() {
        database.map { sqlite3_close($0) }
        database = nil
        try? FileManager.default.removeItem(at: directory)
        imageMemory.removeAll()
        inFlight.removeAll()
    }

    public func cleanup(maxEntries: Int, maxBytes: Int64) {
        let stats = statistics()
        guard stats.assetCount > maxEntries || stats.totalBytes > maxBytes else { return }
        openDatabase(); guard let database else { return }
        while true {
            let current = statistics()
            guard current.assetCount > maxEntries || current.totalBytes > maxBytes else { break }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT key FROM assets ORDER BY accessed ASC LIMIT 1", -1, &statement, nil) == SQLITE_OK else { break }
            guard sqlite3_step(statement) == SQLITE_ROW, let keyPointer = sqlite3_column_text(statement, 0) else { sqlite3_finalize(statement); break }
            let key = String(cString: keyPointer); sqlite3_finalize(statement)
            let paths = [sourceURL(key)] + variantPaths(key: key)
            paths.forEach { try? FileManager.default.removeItem(at: $0) }
            exec("DELETE FROM variants WHERE asset_key='\(key.replacingOccurrences(of: "'", with: "''"))'; DELETE FROM assets WHERE key='\(key.replacingOccurrences(of: "'", with: "''"))';")
        }
    }

    private func variantPaths(key: String) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("\(key)-") && $0.pathExtension == "bgra" }) ?? []
    }

    private func exec(_ sql: String) { _ = sqlite3_exec(database, sql, nil, nil, nil) }

    public func prefetch(for item: BaseItem, api: APIClient) async {
        guard let candidate = logoCandidate(for: item, api: api) else { return }
        _ = await imageData(for: candidate)
    }

    /// Returns preserved source bytes. The URL is used only as an identity; access tokens are not stored.
    public func imageData(for url: URL) async -> Data? {
        let key = Self.stableHash(Self.identity(for: url))
        let source = sourceURL(key)
        if let data = try? Data(contentsOf: source) {
            SolfinLog.debug("image cache hit key=\(key)", category: .cache)
            return data
        }
        if let task = inFlight[key] { return await task.value }
        let task = Task<Data?, Never> { [directory] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let image = NSImage(data: data) else { return nil }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let rep = image.representations.first
                try data.write(to: source, options: .atomic)
                self.recordSource(key: key, url: url, bytes: data.count, mime: http.mimeType, width: rep?.pixelsWide, height: rep?.pixelsHigh)
                return data
            } catch {
                SolfinLog.error("image cache failed: \(error.localizedDescription)", category: .cache)
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    public func image(for url: URL) async -> NSImage? {
        let key = Self.stableHash(Self.identity(for: url))
        if let image = imageMemory[key] { return image }
        guard let data = await imageData(for: url), let image = NSImage(data: data) else { return nil }
        imageMemory[key] = image
        return image
    }

    public func overlay(for item: BaseItem, api: APIClient, downloadIfNeeded: Bool) async -> MPVProcess.OverlayImage? {
        guard let candidate = logoCandidate(for: item, api: api) else { return nil }
        let key = Self.stableHash(Self.identity(for: candidate))
        let variant = "bgra-900x220-v\(overlayVersion)"
        let bgra = directory.appendingPathComponent("\(key)-\(variant).bgra")
        guard downloadIfNeeded || FileManager.default.fileExists(atPath: bgra.path) else { return nil }
        if let derived = variantMetadata(key: key, variant: variant), FileManager.default.fileExists(atPath: bgra.path) {
            return MPVProcess.OverlayImage(path: bgra.path, width: derived.width, height: derived.height)
        }
        guard let data = await imageData(for: candidate), let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return try? writeOverlay(cgImage, key: key, variant: variant, url: candidate, bgra: bgra)
    }

    private func writeOverlay(_ cgImage: CGImage, key: String, variant: String, url: URL, bgra: URL) throws -> MPVProcess.OverlayImage? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scale = min(900.0 / Double(cgImage.width), 220.0 / Double(cgImage.height), 1)
        let width = max(1, Int(Double(cgImage.width) * scale)), height = max(1, Int(Double(cgImage.height) * scale))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .high; ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        try Data(bytes).write(to: bgra, options: .atomic)
        recordVariant(key: key, variant: variant, path: bgra, width: width, height: height, bytes: bytes.count)
        return MPVProcess.OverlayImage(path: bgra.path, width: width, height: height)
    }

    private func logoCandidate(for item: BaseItem, api: APIClient) -> URL? {
        if let tag = item.imageTags?["Logo"], let url = api.logoImageURL(itemId: item.id, tag: tag, maxWidth: 900) { return url }
        if item.type == "Episode", let parent = item.parentLogoItemId ?? item.seriesId,
           let url = api.logoImageURL(itemId: parent, tag: item.parentLogoImageTag, maxWidth: 900) { return url }
        return nil
    }
    private func sourceURL(_ key: String) -> URL { directory.appendingPathComponent("\(key).source") }
    private struct VariantInfo { let width: Int; let height: Int }
    private func variantMetadata(key: String, variant: String) -> VariantInfo? {
        openDatabase(); guard let database else { return nil }
        var statement: OpaquePointer?; let sql = "SELECT width,height FROM variants WHERE asset_key=? AND variant=? AND conversion_version=?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }; defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient); sqlite3_bind_text(statement, 2, variant, -1, sqliteTransient); sqlite3_bind_int(statement, 3, Int32(overlayVersion))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }; return VariantInfo(width: Int(sqlite3_column_int(statement, 0)), height: Int(sqlite3_column_int(statement, 1)))
    }
    private static func identity(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let queryItems = components?.queryItems {
            components?.queryItems = queryItems.filter { $0.name != "api_key" }
        }
        return components?.url?.absoluteString ?? url.absoluteString
    }
    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 { hash ^= UInt64(byte); hash &*= 0x100000001b3 }
        return String(hash, radix: 16)
    }
}
