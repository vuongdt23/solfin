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

/// Stores tokens in the Keychain and server/account metadata in UserDefaults.
/// Each server + user pair has a distinct credential, allowing multiple servers
/// and multiple accounts to coexist without replacing one another.
public struct CredentialStore {
    private let defaults: UserDefaults
    private let service = "Solfin"
    private let deviceIdKey = "solfin.deviceId"
    private let sessionsKey = "solfin.sessions"
    private let legacySessionKey = "solfin.session"
    private let activeSessionKey = "solfin.activeSession"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        try setToken(session.accessToken, account: account)
        // Remove the v1 token only after it has been safely copied to its namespaced account.
        deleteToken(account: session.userId)
        var sessions = loadSessionMetadata()
        var meta = session
        meta.accessToken = ""
        sessions.removeAll { $0.id == session.id }
        sessions.append(meta)
        defaults.set(try JSONEncoder().encode(sessions), forKey: sessionsKey)
        defaults.set(session.id, forKey: activeSessionKey)
        defaults.removeObject(forKey: legacySessionKey)
    }

    public func loadSessions() -> [ServerSession] {
        var sessions = loadSessionMetadata().compactMap { meta -> ServerSession? in
            guard let token = getToken(account: Self.keychainAccount(for: meta)) else { return nil }
            var session = meta
            session.accessToken = token
            return session
        }
        // Migration from v1: retain its original Keychain account so the old
        // session remains usable, then persist it alongside any new sessions.
        if let legacy = loadLegacySession(), !sessions.contains(where: { $0.id == legacy.id }) {
            sessions.append(legacy)
            try? save(legacy)
        }
        return sessions
    }

    public func loadSession() -> ServerSession? {
        let sessions = loadSessions()
        if let activeID = defaults.string(forKey: activeSessionKey),
           let active = sessions.first(where: { $0.id == activeID }) {
            return active
        }
        return sessions.first
    }

    public func setActiveSession(_ session: ServerSession) {
        defaults.set(session.id, forKey: activeSessionKey)
    }

    public func remove(_ session: ServerSession) {
        deleteToken(account: Self.keychainAccount(for: session))
        let legacyAccount = "\(session.serverURL.absoluteString)|\(session.userId)"
        if legacyAccount != Self.keychainAccount(for: session) { deleteToken(account: legacyAccount) }
        deleteToken(account: session.userId)
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
    public func clear() {
        guard let session = loadSession() else { return }
        remove(session)
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
