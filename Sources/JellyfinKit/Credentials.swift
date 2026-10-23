import Foundation
import Security

/// Persisted server session: the reusable pieces needed to rebuild an authenticated client.
public struct ServerSession: Codable, Sendable, Identifiable {
    public var serverURL: URL
    public var userId: String
    public var userName: String
    public var accessToken: String

    /// A stable account identity even when the same Jellyfin user ID exists on
    /// more than one server.
    public var id: String { "\(Self.normalizedServerURL(serverURL))|\(userId)" }

    public init(serverURL: URL, userId: String, userName: String, accessToken: String) {
        self.serverURL = serverURL
        self.userId = userId
        self.userName = userName
        self.accessToken = accessToken
    }

    fileprivate static func normalizedServerURL(_ url: URL) -> String {
        guard let original = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = original.scheme?.lowercased(),
              let host = original.host?.lowercased() else { return url.absoluteString }
        var normalized = URLComponents()
        normalized.scheme = scheme
        normalized.host = host
        if !((scheme == "http" && original.port == 80)
             || (scheme == "https" && original.port == 443)) {
            normalized.port = original.port
        }
        let path = original.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        normalized.percentEncodedPath = path.isEmpty ? "" : "/\(path)"
        return normalized.string ?? url.absoluteString
    }
}

/// Stores tokens in a private plaintext file (default) or optional Keychain;
/// server/account metadata remains in UserDefaults.
/// Each server + user pair has a distinct credential, allowing multiple servers
/// and multiple accounts to coexist without replacing one another.
public struct CredentialStore {
    private let defaults: UserDefaults
    private let service = "Solfin"
    private let deviceIdKey = "solfin.deviceId"
    private let sessionsKey = "solfin.sessions"
    private let legacySessionKey = "solfin.session"
    private let activeSessionKey = "solfin.activeSession"
    public static let storageKey = "solfin.credentialStorage"
    private let localFile: LocalCredentialFile

    public init(defaults: UserDefaults = .standard, localDirectory: URL? = nil) {
        self.defaults = defaults
        self.localFile = LocalCredentialFile(directory: localDirectory)
        // Preserve credentials from installations predating the storage picker.
        // They can migrate through Settings without losing their saved accounts.
        if defaults.string(forKey: Self.storageKey) == nil {
            let existingKeychainMetadata = defaults.data(forKey: sessionsKey) != nil
                || defaults.data(forKey: legacySessionKey) != nil
            defaults.set((existingKeychainMetadata ? CredentialStorage.keychain : .localFile).rawValue,
                         forKey: Self.storageKey)
        }
    }

    public var storage: CredentialStorage {
        CredentialStorage(rawValue: defaults.string(forKey: Self.storageKey) ?? "") ?? .localFile
    }

    public var localFileURL: URL { localFile.url }

    /// Uses already-loaded sessions to avoid another Keychain prompt. Commit the
    /// mode only after all tokens are copied successfully. Old Keychain entries
    /// are deliberately retained when opting into local storage (no delete prompts).
    public func changeStorage(to target: CredentialStorage, sessions: [ServerSession]) throws {
        guard target != storage else { return }
        let requiredIDs = Set(loadSessionMetadata().map(\.id))
        guard requiredIDs.isSubset(of: Set(sessions.filter { !$0.accessToken.isEmpty }.map(\.id))) else {
            throw CredentialStorageError.missingSessions
        }
        if target == .localFile {
            try localFile.write(Dictionary(sessions.map { ($0.id, $0.accessToken) }, uniquingKeysWith: { _, new in new }))
        } else {
            for session in sessions {
                try setToken(session.accessToken, account: Self.keychainAccount(for: session))
            }
            // If cleanup fails, keep the old mode selected and report the error.
            try localFile.delete()
        }
        defaults.set(target.rawValue, forKey: Self.storageKey)
    }

    /// A stable per-install device identifier for the MediaBrowser auth header.
    public var deviceId: String {
        if let existing = defaults.string(forKey: deviceIdKey) { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: deviceIdKey)
        return generated
    }

    public func save(_ session: ServerSession) throws {
        let account = Self.keychainAccount(for: session)
        // Store the secret first so a Keychain failure cannot leave metadata that
        // looks like a persisted session but has no usable token.
        if storage == .localFile {
            var tokens = try localFile.read()
            tokens[account] = session.accessToken
            try localFile.write(tokens)
        } else {
            try setToken(session.accessToken, account: account)
            // Remove the v1 token only after copying it to its namespaced account.
            deleteToken(account: session.userId)
        }
        var sessions = loadSessionMetadata()
        var meta = session
        meta.accessToken = ""
        sessions.removeAll { $0.id == session.id }
        sessions.append(meta)
        defaults.set(try JSONEncoder().encode(sessions), forKey: sessionsKey)
        defaults.set(session.id, forKey: activeSessionKey)
        defaults.removeObject(forKey: legacySessionKey)
    }

    public func loadSessions() throws -> [ServerSession] {
        // Local mode never probes Keychain, including its legacy accounts.
        let localTokens = storage == .localFile ? try localFile.read() : [:]
        var sessions = loadSessionMetadata().compactMap { meta -> ServerSession? in
            let token = storage == .localFile ? localTokens[Self.keychainAccount(for: meta)]
                : getToken(account: Self.keychainAccount(for: meta))
            guard let token else { return nil }
            var session = meta
            session.accessToken = token
            return session
        }
        // Migration from v1: retain its original Keychain account so the old
        // session remains usable, then persist it alongside any new sessions.
        if storage == .keychain, let legacy = loadLegacySession(), !sessions.contains(where: { $0.id == legacy.id }) {
            sessions.append(legacy)
            try? save(legacy)
        }
        return sessions
    }

    public func loadSession() throws -> ServerSession? {
        activeSession(in: try loadSessions())
    }

    public func activeSession(in sessions: [ServerSession]) -> ServerSession? {
        if let activeID = defaults.string(forKey: activeSessionKey),
           let active = sessions.first(where: { $0.id == activeID }) {
            return active
        }
        return sessions.first
    }

    public func setActiveSession(_ session: ServerSession) {
        defaults.set(session.id, forKey: activeSessionKey)
    }

    public func remove(_ session: ServerSession) throws {
        if storage == .localFile {
            var tokens = try localFile.read()
            tokens.removeValue(forKey: Self.keychainAccount(for: session))
            if tokens.isEmpty { try localFile.delete() }
            else { try localFile.write(tokens) }
        } else {
            deleteToken(account: Self.keychainAccount(for: session))
            let legacyAccount = "\(session.serverURL.absoluteString)|\(session.userId)"
            if legacyAccount != Self.keychainAccount(for: session) { deleteToken(account: legacyAccount) }
            deleteToken(account: session.userId)
        }
        let remaining = loadSessionMetadata().filter { $0.id != session.id }
        if let data = try? JSONEncoder().encode(remaining) {
            defaults.set(data, forKey: sessionsKey)
        }
        if defaults.string(forKey: activeSessionKey) == session.id {
            if let next = remaining.first { defaults.set(next.id, forKey: activeSessionKey) }
            else { defaults.removeObject(forKey: activeSessionKey) }
        }
        if remaining.isEmpty { defaults.removeObject(forKey: sessionsKey) }
    }

    /// Clears the active account for backwards compatibility with the old sign-out action.
    public func clear() throws {
        guard let session = try loadSession() else { return }
        try remove(session)
    }

    private func loadSessionMetadata() -> [ServerSession] {
        guard let data = defaults.data(forKey: sessionsKey) else { return [] }
        return (try? JSONDecoder().decode([ServerSession].self, from: data)) ?? []
    }

    private func loadLegacySession() -> ServerSession? {
        guard let data = defaults.data(forKey: legacySessionKey),
              var session = try? JSONDecoder().decode(ServerSession.self, from: data),
              let token = getToken(account: session.userId) else { return nil }
        session.accessToken = token
        return session
    }

    private static func keychainAccount(for session: ServerSession) -> String {
        "\(ServerSession.normalizedServerURL(session.serverURL))|\(session.userId)"
    }

    // MARK: - Keychain

    private func setToken(_ token: String, account: String) throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let values: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // Update in place first. Delete-then-add is vulnerable to stale/duplicate
        // Keychain items left by earlier signed or ad-hoc builds and surfaced as
        // errSecDuplicateItem (-25299).
        let updateStatus = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw JellyfinError.keychain(updateStatus)
        }

        var item = identity
        values.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Another process/build may have inserted it between update and add.
            let retryStatus = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
            guard retryStatus == errSecSuccess else { throw JellyfinError.keychain(retryStatus) }
            return
        }
        guard addStatus == errSecSuccess else { throw JellyfinError.keychain(addStatus) }
    }

    private func getToken(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func deleteToken(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
