import Foundation
import Security

/// Persisted server session: the reusable pieces needed to rebuild an authenticated client.
public struct ServerSession: Codable, Sendable {
    public var serverURL: URL
    public var userId: String
    public var userName: String
    public var accessToken: String

    public init(serverURL: URL, userId: String, userName: String, accessToken: String) {
        self.serverURL = serverURL
        self.userId = userId
        self.userName = userName
        self.accessToken = accessToken
    }
}

/// Stores the access token in the Keychain and the non-secret session metadata + DeviceId
/// in UserDefaults. v1 = a single server session.
public struct CredentialStore {
    private let defaults: UserDefaults
    private let service = "Solfin"
    private let deviceIdKey = "solfin.deviceId"
    private let sessionKey = "solfin.session"

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
        // Store the secret first so a Keychain failure cannot leave metadata that
        // looks like a persisted session but has no usable token.
        try setToken(session.accessToken, account: session.userId)
        var meta = session
        meta.accessToken = ""
        defaults.set(try JSONEncoder().encode(meta), forKey: sessionKey)
    }

    public func loadSession() -> ServerSession? {
        guard let data = defaults.data(forKey: sessionKey),
              var meta = try? JSONDecoder().decode(ServerSession.self, from: data),
              let token = getToken(account: meta.userId)
        else { return nil }
        meta.accessToken = token
        return meta
    }

    public func clear() {
        if let data = defaults.data(forKey: sessionKey),
           let meta = try? JSONDecoder().decode(ServerSession.self, from: data) {
            deleteToken(account: meta.userId)
        }
        defaults.removeObject(forKey: sessionKey)
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
