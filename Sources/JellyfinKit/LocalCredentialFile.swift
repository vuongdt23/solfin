import Foundation
import Darwin

public enum CredentialStorage: String, CaseIterable, Identifiable, Sendable {
    case keychain
    case localFile

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .keychain: return "Keychain"
        case .localFile: return "Local file — no prompts"
        }
    }
}

public enum CredentialStorageError: LocalizedError {
    case missingSessions

    public var errorDescription: String? {
        "Some saved credentials are unavailable. Sign in to those servers again or forget them before changing storage."
    }
}

/// Private plaintext storage. Never put tokens in UserDefaults or logs.
/// Atomic replacement happens inside a private directory with a 0600 staging
/// file, so neither the destination nor temporary bytes are world-readable.
struct LocalCredentialFile {
    let directory: URL
    var url: URL { directory.appendingPathComponent("credentials.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Solfin", isDirectory: true)
    }

    func read() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        try secureDirectory()
        try rejectSymlink(url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    func write(_ tokens: [String: String]) throws {
        try secureDirectory()
        let data = try JSONEncoder().encode(tokens)
        let staging = directory.appendingPathComponent(".credentials-\(UUID().uuidString)")
        let fd = open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: staging) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard rename(staging.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func secureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try rejectSymlink(directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func rejectSymlink(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw CocoaError(.fileReadNoPermission)
        }
    }
}
