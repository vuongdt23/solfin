import AppKit
import Foundation
import JellyfinKit

/// Downloads Jellyfin transparent title logos and stores mpv-ready BGRA overlays on disk.
///
/// Detail views prewarm this cache during navigation. Playback then does a quick cache
/// lookup and only falls back to a blocking download on a cold miss, so the first route
/// can still show the logo while repeat launches are instant.
public actor LogoOverlayCache {
    public static let shared = LogoOverlayCache()

    private struct Meta: Codable {
        let width: Int
        let height: Int
    }

    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.directory = base.appendingPathComponent("Solfin/LogoOverlays", isDirectory: true)
        }
    }

    /// Fire-and-forget warmup for navigation/detail screens.
    public func prefetch(for item: BaseItem, api: APIClient) async {
        _ = await overlay(for: item, api: api, downloadIfNeeded: true)
    }

    /// Return a cached overlay, optionally downloading and caching on miss.
    public func overlay(for item: BaseItem, api: APIClient,
                        downloadIfNeeded: Bool) async -> MPVProcess.OverlayImage? {
        guard let candidate = logoCandidate(for: item, api: api) else { return nil }
        let key = Self.stableHash(candidate.cacheIdentity)
        if let cached = cachedOverlay(forKey: key) {
            SolfinLog.debug("logo cache hit key=\(key)", category: .cache)
            return cached
        }
        SolfinLog.info("logo cache miss key=\(key) downloadIfNeeded=\(downloadIfNeeded)", category: .cache)
        guard downloadIfNeeded else { return nil }

        do {
            let started = Date()
            let (data, response) = try await URLSession.shared.data(from: candidate.url)
            SolfinLog.info("logo download finished bytes=\(data.count) in \(Int(Date().timeIntervalSince(started) * 1000))ms url=\(SolfinLog.redactedURL(candidate.url))", category: .cache)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return try writeBGRAOverlay(cgImage: cgImage, key: key)
        } catch {
            SolfinLog.error("logo overlay failed: \(error.localizedDescription)", category: .cache)
            return nil
        }
    }

    private func logoCandidate(for item: BaseItem, api: APIClient) -> (url: URL, cacheIdentity: String)? {
        if let tag = item.imageTags?["Logo"],
           let url = api.logoImageURL(itemId: item.id, tag: tag, maxWidth: 900) {
            return (url, "\(api.baseURL.absoluteString)|\(item.id)|\(tag)")
        }

        if item.type == "Episode", let parentId = item.parentLogoItemId ?? item.seriesId,
           let url = api.logoImageURL(itemId: parentId, tag: item.parentLogoImageTag, maxWidth: 900) {
            return (url, "\(api.baseURL.absoluteString)|\(parentId)|\(item.parentLogoImageTag ?? "latest")")
        }

        return nil
    }

    private func cachedOverlay(forKey key: String) -> MPVProcess.OverlayImage? {
        let bgra = bgraURL(forKey: key)
        let metaURL = metaURL(forKey: key)
        guard FileManager.default.fileExists(atPath: bgra.path),
              let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: data) else {
            return nil
        }
        return MPVProcess.OverlayImage(path: bgra.path, width: meta.width, height: meta.height)
    }

    private func writeBGRAOverlay(cgImage: CGImage, key: String) throws -> MPVProcess.OverlayImage? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let maxWidth = 900
        let maxHeight = 220
        let scale = min(Double(maxWidth) / Double(cgImage.width),
                        Double(maxHeight) / Double(cgImage.height), 1)
        let width = max(1, Int(Double(cgImage.width) * scale))
        let height = max(1, Int(Double(cgImage.height) * scale))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let bgra = bgraURL(forKey: key)
        let meta = metaURL(forKey: key)
        try Data(bytes).write(to: bgra, options: .atomic)
        try JSONEncoder().encode(Meta(width: width, height: height)).write(to: meta, options: .atomic)
        SolfinLog.info("logo cached key=\(key) size=\(width)x\(height)", category: .cache)
        return MPVProcess.OverlayImage(path: bgra.path, width: width, height: height)
    }

    private func bgraURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).bgra")
    }

    private func metaURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
