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
    @Published var isAuthenticating = false
    @Published var playbackError: String?
    @Published var isValidatingStoredSession = false

    // Settings (persisted lightly in UserDefaults).
    @AppStorage("solfin.mpvPath") var mpvPathOverride: String = ""
    @AppStorage("solfin.serverURL") var lastServerURL: String = "http://localhost:8096"
    @AppStorage("solfin.preferredAudioLanguage") var preferredAudioLanguage: String = ""
    @AppStorage("solfin.preferredSubtitleLanguage") var preferredSubtitleLanguage: String = ""

    private let store = CredentialStore()
    private(set) var api: APIClient

    /// Path to the bundled mpv config-dir (mpv.conf + solfin-osc), inside the app bundle.
    var mpvConfigDir: String? {
        Bundle.main.resourcePath.map { $0 + "/mpv" }
    }

    init() {
        let info = ClientInfo(deviceId: store.deviceId)
        let saved = store.loadSessions()
        let existing = store.loadSession()
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
            savedSessions = store.loadSessions()
            activate(session)
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
        defer { isAuthenticating = false }
        let info = ClientInfo(deviceId: store.deviceId)
        let client = APIClient(baseURL: session.serverURL, clientInfo: info).authenticated(with: session)
        do {
            _ = try await client.views()
            store.setActiveSession(session)
            self.session = session
            api = client
            lastServerURL = session.serverURL.absoluteString
            isAddingServer = false
        } catch {
            loginError = "Could not connect to \(session.serverURL.absoluteString): \(error.localizedDescription)"
        }
    }

    func beginAddingServer() {
        loginError = nil
        isAddingServer = true
    }

    func removeServer(_ session: ServerSession) {
        let wasActive = self.session?.id == session.id
        store.remove(session)
        savedSessions = store.loadSessions()
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
