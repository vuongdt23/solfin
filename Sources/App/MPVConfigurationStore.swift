import Foundation
import AppKit

@MainActor
final class MPVConfigurationStore: ObservableObject {
    enum SaveState: Equatable {
        case clean
        case unsaved
        case saved
        case failed(String)
    }

    @Published private(set) var bundledConfiguration = ""
    @Published var overrideConfiguration = "" {
        didSet {
            guard !isLoading, overrideConfiguration != savedConfiguration else { return }
            saveState = .unsaved
        }
    }
    @Published private(set) var saveState: SaveState = .clean

    private var savedConfiguration = ""
    private var isLoading = false

    static var overrideDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Solfin", isDirectory: true)
    }

    static var overrideFileURL: URL {
        overrideDirectoryURL.appendingPathComponent("mpv-overrides.conf")
    }

    static var activeOverridePath: String? {
        let url = overrideFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let value = try? String(contentsOf: url, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return url.path
    }

    var hasUnsavedChanges: Bool { overrideConfiguration != savedConfiguration }
    var overridePath: String { Self.overrideFileURL.path }

    func load(bundledConfigDir: String?) {
        isLoading = true
        defer { isLoading = false }

        if let bundledConfigDir {
            let bundledURL = URL(fileURLWithPath: bundledConfigDir).appendingPathComponent("mpv.conf")
            bundledConfiguration = (try? String(contentsOf: bundledURL, encoding: .utf8))
                ?? "The bundled mpv configuration could not be loaded."
        } else {
            bundledConfiguration = "The bundled mpv configuration is unavailable."
        }

        overrideConfiguration = (try? String(contentsOf: Self.overrideFileURL, encoding: .utf8)) ?? ""
        savedConfiguration = overrideConfiguration
        saveState = .clean
    }

    func save() {
        let normalized = overrideConfiguration.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validate(normalized) {
            saveState = .failed(error)
            return
        }

        do {
            try FileManager.default.createDirectory(at: Self.overrideDirectoryURL,
                                                    withIntermediateDirectories: true)
            if normalized.isEmpty {
                if FileManager.default.fileExists(atPath: Self.overrideFileURL.path) {
                    try FileManager.default.removeItem(at: Self.overrideFileURL)
                }
                overrideConfiguration = ""
            } else {
                let file = normalized + "\n"
                try file.write(to: Self.overrideFileURL, atomically: true, encoding: .utf8)
                overrideConfiguration = file
            }
            savedConfiguration = overrideConfiguration
            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    func revert() {
        isLoading = true
        overrideConfiguration = savedConfiguration
        isLoading = false
        saveState = .clean
    }

    func clear() {
        overrideConfiguration = ""
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: Self.overrideDirectoryURL,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([Self.overrideFileURL])
    }

    private func validate(_ configuration: String) -> String? {
        for (offset, rawLine) in configuration.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") { continue }
            guard let separator = line.firstIndex(of: "="), separator != line.startIndex else {
                return "Line \(offset + 1) must use option=value syntax."
            }
            let option = line[..<separator].trimmingCharacters(in: .whitespaces)
            if option.contains(" ") || option.hasPrefix("--") {
                return "Line \(offset + 1) has an invalid option name. Use option=value without --."
            }
        }
        return nil
    }
}
