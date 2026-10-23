import AppKit
import CryptoKit
import ImageIO
import Vision

/// Normalized face rectangles use a top-left origin, like the SwiftUI canvas.
public struct ArtworkFaceAnalysis: Codable, Sendable {
    public let faces: [CGRect]
    public init(faces: [CGRect]) { self.faces = faces }
}

/// Local-only Vision analysis. Disk entries are keyed by source bytes, never server
/// URLs or credentials. Empty detections are cached too; failures remain retryable.
public actor ArtworkFaceCache {
    public static let shared = ArtworkFaceCache()
    private var memory: [String: ArtworkFaceAnalysis] = [:]
    private var inFlight: [String: Task<ArtworkFaceAnalysis?, Never>] = [:]
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Solfin/ArtworkFaces-v1", isDirectory: true)
    }

    public func analysis(for url: URL) async -> ArtworkFaceAnalysis? {
        guard let data = await MediaAssetCache.shared.imageData(for: url) else { return nil }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let result = memory[key] { return result }
        let file = directory.appendingPathComponent(key).appendingPathExtension("json")
        if let stored = try? Data(contentsOf: file),
           let result = try? JSONDecoder().decode(ArtworkFaceAnalysis.self, from: stored) {
            remember(result, key: key)
            return result
        }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> ArtworkFaceAnalysis? in
            // Vision gets a small, orientation-correct copy, not a multi-megapixel
            // image. Detection never runs on the main actor.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200
                  ] as CFDictionary) else { return nil }
            let request = VNDetectFaceRectanglesRequest()
            do {
                try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                let faces = (request.results ?? []).filter { $0.confidence >= 0.5 }.map { observation in
                    let rect = observation.boundingBox
                    return CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
                }
                return ArtworkFaceAnalysis(faces: faces)
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            remember(result, key: key)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let encoded = try? JSONEncoder().encode(result) { try? encoded.write(to: file, options: .atomic) }
        }
        return result
    }

    private func remember(_ result: ArtworkFaceAnalysis, key: String) {
        if memory.count >= 128 { memory.removeAll(keepingCapacity: true) }
        memory[key] = result
    }
}

/// Pure layout math, independent of Vision and SwiftUI. Never zooms further than
/// aspect-fill. If the faces cannot fit together, relaxes the scale and lets the
/// view extend the uncovered edges with a blurred backdrop.
public struct ArtworkFraming {
    public let imageFrame: CGRect
    public let needsEdgeExtension: Bool

    public init(imageSize: CGSize, canvasSize: CGSize, faces: [CGRect]) {
        guard imageSize.width > 0, imageSize.height > 0,
              canvasSize.width > 0, canvasSize.height > 0 else {
            imageFrame = .zero
            needsEdgeExtension = false
            return
        }
        let fillScale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let fitScale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let bounds = faces.filter { !$0.isEmpty && !$0.isNull }.map { face in
            // Add generous headroom: Vision detects facial features, not hair.
            CGRect(x: max(0, face.minX - face.width * 0.2),
                   y: max(0, face.minY - face.height * 0.55),
                   width: min(1, face.maxX + face.width * 0.2) - max(0, face.minX - face.width * 0.2),
                   height: min(1, face.maxY + face.height * 0.25) - max(0, face.minY - face.height * 0.55))
        }.reduce(CGRect.null) { $0.union($1) }
        var scale = fillScale
        if !bounds.isNull {
            let faceScale = min(canvasSize.width * 0.92 / (bounds.width * imageSize.width),
                                canvasSize.height * 0.72 / (bounds.height * imageSize.height))
            scale = max(fitScale, min(fillScale, faceScale))
        }
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let defaultX = width < canvasSize.width ? canvasSize.width - width : (canvasSize.width - width) / 2
        let defaultY = height < canvasSize.height ? 0 : (canvasSize.height - height) * 0.18

        func offset(defaultValue: CGFloat, length: CGFloat, canvas: CGFloat,
                    faceMin: CGFloat, faceMax: CGFloat, safeMin: CGFloat, safeMax: CGFloat) -> CGFloat {
            let allowedMin = min(0, canvas - length)
            let allowedMax = max(0, canvas - length)
            guard !bounds.isNull else { return defaultValue }
            let lower = max(allowedMin, canvas * safeMin - faceMin * length)
            let upper = min(allowedMax, canvas * safeMax - faceMax * length)
            if lower <= upper { return min(max(defaultValue, lower), upper) }
            // Edge faces cannot always have full margins without exposing empty
            // space. Prioritize the face center, while staying within the canvas.
            let centered = canvas * (safeMin + safeMax) / 2 - (faceMin + faceMax) * length / 2
            return min(max(centered, allowedMin), allowedMax)
        }
        let x = offset(defaultValue: defaultX, length: width, canvas: canvasSize.width,
                       faceMin: bounds.minX, faceMax: bounds.maxX, safeMin: 0.04, safeMax: 0.96)
        let y = offset(defaultValue: defaultY, length: height, canvas: canvasSize.height,
                       faceMin: bounds.minY, faceMax: bounds.maxY, safeMin: 0.06, safeMax: 0.78)
        imageFrame = CGRect(x: x, y: y, width: width, height: height)
        needsEdgeExtension = width < canvasSize.width - 1 || height < canvasSize.height - 1
    }
}
