import Foundation

/// Locates and launches the external mpv binary with our own config directory.
public final class MPVProcess {
    public struct LaunchError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    public struct OverlayImage: Sendable {
        public let path: String
        public let width: Int
        public let height: Int

        public init(path: String, width: Int, height: Int) {
            self.path = path
            self.width = width
            self.height = height
        }
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

    private static var writableDirectories: [(String, String)] {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Solfin/mpv", isDirectory: true)
        return [
            ("--watch-later-dir=", "watch-later"),
            ("--demuxer-cache-dir=", "demuxer-cache"),
            ("--gpu-shader-cache-dir=", "gpu-shader-cache"),
            ("--icc-cache-dir=", "icc-cache"),
        ].map { ($0.0, base.appendingPathComponent($0.1, isDirectory: true).path) }
    }

    private static func supportsModernAutoHWDec(binaryPath: String) -> Bool {
        let version = Process()
        version.executableURL = URL(fileURLWithPath: binaryPath)
        version.arguments = ["--no-config", "--version"]
        let output = Pipe()
        version.standardOutput = output
        version.standardError = Pipe()
        do { try version.run() } catch { return false }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        version.waitUntilExit()
        guard let line = text.components(separatedBy: .newlines).first,
              line.hasPrefix("mpv "),
              let match = line.range(of: #"(\d+)\.(\d+)"#, options: .regularExpression) else { return false }
        let numbers = line[match].split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 2 else { return false }
        return numbers[0] > 0 || numbers[1] >= 40
    }

    /// Launch mpv. `configDir` should point at the bundled Resources/mpv (mpv.conf + OSC).
    /// `mediaTitle` overrides mpv's `media-title` (otherwise it falls back to the ugly
    /// stream URL filename) so the OSC shows the real Jellyfin item name.
    public func launch(binaryPath: String, configDir: String?, additionalConfigPath: String? = nil,
                       initialURL: String?, startSeconds: Double?, mediaTitle: String? = nil,
                       logoOverlay: OverlayImage? = nil,
                       mpvLogPath: String? = nil, mpvMessageLevel: String? = nil) throws {
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
        do {
            for (option, path) in Self.writableDirectories {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                args.append("\(option)\(path)")
            }
        } catch {
            throw LaunchError(message: "Could not create Solfin's mpv data directories: \(error.localizedDescription)")
        }
        if Self.supportsModernAutoHWDec(binaryPath: binaryPath) { args.append("--hwdec=auto") }
        let envLogPath = ProcessInfo.processInfo.environment["SOLFIN_MPV_LOG"]
        if let logPath = mpvLogPath ?? envLogPath, !logPath.isEmpty {
            args.append("--log-file=\(logPath)")
            args.append("--msg-level=\(mpvMessageLevel ?? "all=debug")")
        }
        // Load after the bundled mpv.conf so user values override bundled defaults.
        if let additionalConfigPath, !additionalConfigPath.isEmpty {
            args.append("--include=\(additionalConfigPath)")
        }
        if let start = startSeconds, start > 0 { args.append("--start=\(Int(start))") }
        if let mediaTitle, !mediaTitle.isEmpty { args.append("--force-media-title=\(mediaTitle)") }
        if let logoOverlay {
            args.append("--script-opts=solfin-osc-logo_path=\(logoOverlay.path),solfin-osc-logo_width=\(logoOverlay.width),solfin-osc-logo_height=\(logoOverlay.height)")
        }
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
