import Foundation
import SwiftUI
import JellyfinKit
import PlaybackEngine

@MainActor
final class AppState: ObservableObject {
    @Published var session: ServerSession?
    @Published private(set) var savedSessions: [ServerSession] = []
    @Published var isAddingServer = false
    @Published var loginError: String?
    @Published var serverSwitchError: String?
    @Published private(set) var serverToReauthenticate: ServerSession?
    @Published var isAuthenticating = false
    @Published var playbackError: String?
    @Published var isValidatingStoredSession = false
    @Published private(set) var credentialStorage: CredentialStorage = .localFile
    @Published var credentialStorageError: String?
    var localCredentialFileURL: URL { store.localFileURL }

    // Settings (persisted lightly in UserDefaults).
    @AppStorage("solfin.mpvPath") var mpvPathOverride: String = ""
    @AppStorage("solfin.serverURL") var lastServerURL: String = "http://localhost:8096"
    @AppStorage("solfin.preferredAudioLanguage") var preferredAudioLanguage: String = ""
    @AppStorage("solfin.preferredSubtitleLanguage") var preferredSubtitleLanguage: String = ""

    private let store = CredentialStore()
    private(set) var api: APIClient

    // Retain only the last decorative stack IDs across Home view recreation.
    // Scope by session so switching servers/users never mixes library histories.
    var libraryPosterHistory: [String: [String]] = [:]

    /// Path to the bundled mpv config-dir (mpv.conf + solfin-osc), inside the app bundle.
    var mpvConfigDir: String? {
        Bundle.main.resourcePath.map { $0 + "/mpv" }
    }

    init() {
        let info = ClientInfo(deviceId: store.deviceId)
        var saved: [ServerSession] = []
        do { saved = try store.loadSessions() }
        catch { credentialStorageError = "Could not load saved credentials: \(error.localizedDescription)" }
        let existing = store.activeSession(in: saved)
        credentialStorage = store.storage
        self.savedSessions = saved
        let base = existing?.serverURL ?? URL(string: "http://localhost:8096")!
        self.api = APIClient(baseURL: base, clientInfo: info)
        if let existing {
            self.session = existing
            self.api = api.authenticated(with: existing)
            self.isValidatingStoredSession = true
        }
    }

    var isSignedIn: Bool { session != nil && !isAddingServer }

    /// Verifies a restored session before showing the library. If the server has
    /// moved or is no longer reachable, return the user to login with an explicit
    /// recovery message instead of leaving them trapped in a broken shell.
    func validateStoredSession() async {
        guard isValidatingStoredSession else { return }
        defer { isValidatingStoredSession = false }
        guard session != nil else { return }
        do {
            _ = try await api.views()
        } catch {
            let failedServer = session?.serverURL.absoluteString ?? lastServerURL
            session = nil
            isAddingServer = true
            loginError = "Could not connect to \(failedServer). Choose another saved server or sign in to a different server."
        }
    }

    func signIn(serverURL: String, username: String, password: String) async {
        isAuthenticating = true
        loginError = nil
        defer { isAuthenticating = false }
        guard let url = URL(string: serverURL),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil else { loginError = "Enter a valid HTTP or HTTPS server address."; return }
        let info = ClientInfo(deviceId: store.deviceId)
        let client = APIClient(baseURL: url, clientInfo: info)
        do {
            let session = try await client.login(username: username, password: password)
            try store.save(session)
            // The secret is already in memory; avoid rereading every Keychain item.
            savedSessions.removeAll { $0.id == session.id }
            savedSessions.append(session)
            activate(session)
            serverToReauthenticate = nil
            serverSwitchError = nil
            isAddingServer = false
            self.lastServerURL = serverURL
        } catch {
            loginError = error.localizedDescription
        }
    }

    func switchServer(to session: ServerSession) async {
        guard self.session?.id != session.id else { isAddingServer = false; return }
        isAuthenticating = true
        loginError = nil
        serverSwitchError = nil
        defer { isAuthenticating = false }
        let info = ClientInfo(deviceId: store.deviceId)
        let client = APIClient(baseURL: session.serverURL, clientInfo: info).authenticated(with: session)
        do {
            _ = try await client.views()
            store.setActiveSession(session)
            self.session = session
            api = client
            lastServerURL = session.serverURL.absoluteString
            serverToReauthenticate = nil
            serverSwitchError = nil
            isAddingServer = false
        } catch {
            let message = "Could not switch to \(session.serverURL.absoluteString): \(error.localizedDescription)"
            loginError = message
            serverSwitchError = message
            serverToReauthenticate = session
        }
    }

    func beginAddingServer() {
        serverToReauthenticate = nil
        loginError = nil
        isAddingServer = true
    }

    func beginReauthenticating(_ session: ServerSession) {
        serverToReauthenticate = session
        serverSwitchError = nil
        loginError = nil
        isAddingServer = true
    }

    func cancelAddingServer() {
        serverToReauthenticate = nil
        isAddingServer = false
        loginError = nil
    }

    func removeServer(_ session: ServerSession) {
        let wasActive = self.session?.id == session.id
        do { try store.remove(session) }
        catch {
            credentialStorageError = "Could not forget this server: \(error.localizedDescription)"
            return
        }
        savedSessions.removeAll { $0.id == session.id }
        if wasActive {
            self.session = nil
            isAddingServer = false
            let info = ClientInfo(deviceId: store.deviceId)
            api = APIClient(baseURL: URL(string: lastServerURL) ?? URL(string: "http://localhost:8096")!,
                            clientInfo: info)
            if let replacement = savedSessions.first {
                Task { await switchServer(to: replacement) }
            }
        }
    }

    func changeCredentialStorage(to target: CredentialStorage) {
        credentialStorageError = nil
        do {
            try store.changeStorage(to: target, sessions: savedSessions)
            credentialStorage = store.storage
        } catch {
            credentialStorageError = "Could not change credential storage: \(error.localizedDescription)"
        }
    }

    func signOut() {
        guard let session else { return }
        removeServer(session)
    }

    private func activate(_ session: ServerSession) {
        store.setActiveSession(session)
        self.session = session
        api = APIClient(baseURL: session.serverURL, clientInfo: ClientInfo(deviceId: store.deviceId))
            .authenticated(with: session)
        lastServerURL = session.serverURL.absoluteString
    }

    func makePlaybackConfig() -> PlaybackController.Config {
        PlaybackController.Config(
            mpvBinaryPath: mpvPathOverride.isEmpty ? nil : mpvPathOverride,
            configDir: mpvConfigDir,
            additionalConfigPath: MPVConfigurationStore.activeOverridePath,
            preferredAudioLanguage: preferredAudioLanguage.nilIfEmpty,
            preferredSubtitleLanguage: preferredSubtitleLanguage.nilIfEmpty
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
