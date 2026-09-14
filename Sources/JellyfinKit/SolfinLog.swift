import Foundation

public enum SolfinLogLevel: String, CaseIterable, Identifiable, Sendable {
    case off
    case error
    case info
    case debug
    case trace

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .error: return "Errors"
        case .info: return "Info"
        case .debug: return "Debug"
        case .trace: return "Trace"
        }
    }

    var priority: Int {
        switch self {
        case .off: return 0
        case .error: return 1
        case .info: return 2
        case .debug: return 3
        case .trace: return 4
        }
    }

    public var mpvMessageLevel: String? {
        switch self {
        case .off: return nil
        case .error: return "all=error"
        case .info: return "all=info"
        case .debug: return "all=debug"
        case .trace: return "all=trace"
        }
    }
}

public enum SolfinLogCategory: String, Sendable {
    case app
    case api
    case playback
    case mpv
    case cache
    case persistence
}

public struct SolfinLogTimer: Sendable {
    private let start = Date()
    private let category: SolfinLogCategory
    private let name: String
    private let level: SolfinLogLevel

    public init(_ name: String, category: SolfinLogCategory, level: SolfinLogLevel = .debug) {
        self.name = name
        self.category = category
        self.level = level
    }

    public func finish(_ detail: String = "") {
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        SolfinLog.write(level, "\(name) completed in \(ms)ms\(detail.isEmpty ? "" : " · \(detail)")", category: category)
    }
}

public enum SolfinLog {
    public static let levelKey = "solfin.logging.level"
    public static let directoryKey = "solfin.logging.directory"

    private static let lock = NSLock()
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public static var defaultDirectoryPath: String {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return base.appendingPathComponent("Logs/Solfin", isDirectory: true).path
    }

    public static var currentLevel: SolfinLogLevel {
        get {
            let raw = UserDefaults.standard.string(forKey: levelKey) ?? SolfinLogLevel.info.rawValue
            return SolfinLogLevel(rawValue: raw) ?? .info
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: levelKey) }
    }

    public static var directoryPath: String {
        get {
            let raw = UserDefaults.standard.string(forKey: directoryKey) ?? ""
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultDirectoryPath : raw
        }
        set { UserDefaults.standard.set(newValue, forKey: directoryKey) }
    }

    public static var directoryURL: URL {
        URL(fileURLWithPath: (directoryPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    public static func write(_ level: SolfinLogLevel, _ message: String,
                             category: SolfinLogCategory = .app,
                             file: StaticString = #fileID,
                             line: UInt = #line) {
        let configured = currentLevel
        guard configured != .off, level.priority <= configured.priority else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let path = directoryURL.appendingPathComponent("solfin.log")
            let stamp = dateFormatter.string(from: Date())
            let entry = "[\(stamp)] [\(level.rawValue.uppercased())] [\(category.rawValue)] \(file):\(line) \(message)\n"
            append(entry, to: path)
        } catch {
            // Logging must never affect app behavior.
        }
    }

    public static func error(_ message: String, category: SolfinLogCategory = .app,
                             file: StaticString = #fileID, line: UInt = #line) {
        write(.error, message, category: category, file: file, line: line)
    }

    public static func info(_ message: String, category: SolfinLogCategory = .app,
                            file: StaticString = #fileID, line: UInt = #line) {
        write(.info, message, category: category, file: file, line: line)
    }

    public static func debug(_ message: String, category: SolfinLogCategory = .app,
                             file: StaticString = #fileID, line: UInt = #line) {
        write(.debug, message, category: category, file: file, line: line)
    }

    public static func trace(_ message: String, category: SolfinLogCategory = .app,
                             file: StaticString = #fileID, line: UInt = #line) {
        write(.trace, message, category: category, file: file, line: line)
    }

    public static func makeMPVLogPath(title: String?) -> String? {
        guard currentLevel != .off, currentLevel.mpvMessageLevel != nil else { return nil }
        let dir = directoryURL.appendingPathComponent("mpv", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            return dir.appendingPathComponent("\(stamp)-\(sanitize(title ?? "playback")).log").path
        } catch {
            return nil
        }
    }

    public static func redactedURL(_ url: URL?) -> String {
        guard let url else { return "<nil>" }
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.path }
        comps.queryItems = comps.queryItems?.map { item in
            let sensitive = ["api_key", "access_token", "token", "X-Emby-Token"].contains(item.name)
            return URLQueryItem(name: item.name, value: sensitive ? "<redacted>" : item.value)
        }
        return comps.string ?? url.path
    }

    private static func append(_ string: String, to url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = string.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. "))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return String((result.isEmpty ? "playback" : result).prefix(80))
    }
}
