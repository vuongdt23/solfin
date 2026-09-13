import Foundation

/// Locates and launches the external mpv binary with our own config directory.
public final class MPVProcess {
    public struct LaunchError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    private var process: Process?
    public let socketPath: String
    public var onExit: ((Int32) -> Void)?

    /// Search order: explicit override, Homebrew (arm64 then Intel), then PATH.
    public static func locateBinary(override: String? = nil) -> String? {
        if let override, FileManager.default.isExecutableFile(atPath: override) { return override }
        let candidates = ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv", "/usr/bin/mpv"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        // Fall back to `which mpv`.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "mpv"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    public init() {
        self.socketPath = NSTemporaryDirectory() + "solfin-mpv-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8)).sock"
    }

    /// Launch mpv. `configDir` should point at the bundled Resources/mpv (mpv.conf + OSC).
    /// `mediaTitle` overrides mpv's `media-title` (otherwise it falls back to the ugly
    /// stream URL filename) so the OSC shows the real Jellyfin item name.
    public func launch(binaryPath: String, configDir: String?, initialURL: String?,
                       startSeconds: Double?, mediaTitle: String? = nil) throws {
        // Stale socket from a prior crash would block bind on mpv's side.
        try? FileManager.default.removeItem(atPath: socketPath)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        var args = [
            "--input-ipc-server=\(socketPath)",
            "--force-window=yes",
            "--fullscreen=yes",
            "--idle=once",
            "--keep-open=no",
            "--title=${media-title}",
        ]
        if let configDir { args.append("--config-dir=\(configDir)") }
        if let start = startSeconds, start > 0 { args.append("--start=\(Int(start))") }
        if let mediaTitle, !mediaTitle.isEmpty { args.append("--force-media-title=\(mediaTitle)") }
        if let initialURL { args.append(initialURL) }
        p.arguments = args

        p.terminationHandler = { [weak self] proc in
            self?.onExit?(proc.terminationStatus)
        }
        do {
            try p.run()
        } catch {
            throw LaunchError(message: "Failed to launch mpv at \(binaryPath): \(error.localizedDescription)")
        }
        process = p
    }

    public var isRunning: Bool { process?.isRunning ?? false }

    public func terminate() {
        process?.terminate()
    }

    public func cleanupSocket() {
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}
