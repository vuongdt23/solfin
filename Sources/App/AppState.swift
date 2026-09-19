import Foundation
import SwiftUI
import JellyfinKit
import PlaybackEngine

@MainActor
final class AppState: ObservableObject {
    @Published var session: ServerSession?
    @Published var loginError: String?
    @Published var isAuthenticating = false
    @Published var playbackError: String?
    @Published var isValidatingStoredSession = false

    // Settings (persisted lightly in UserDefaults).
    @AppStorage("solfin.mpvPath") var mpvPathOverride: String = ""
    @AppStorage("solfin.serverURL") var lastServerURL: String = "http://localhost:8096"

    private let store = CredentialStore()
    private(set) var api: APIClient

    /// Path to the bundled mpv config-dir (mpv.conf + solfin-osc), inside the app bundle.
    var mpvConfigDir: String? {
        Bundle.main.resourcePath.map { $0 + "/mpv" }
    }

    init() {
        let info = ClientInfo(deviceId: store.deviceId)
        let existing = store.loadSession()
        let base = existing?.serverURL ?? URL(string: "http://localhost:8096")!
        self.api = APIClient(baseURL: base, clientInfo: info)
        if let existing {
            self.session = existing
            self.api = api.authenticated(with: existing)
            self.isValidatingStoredSession = true
        }
    }

    var isSignedIn: Bool { session != nil }

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
            let info = ClientInfo(deviceId: store.deviceId)
            session = nil
            api = APIClient(baseURL: URL(string: lastServerURL) ?? URL(string: "http://localhost:8096")!, clientInfo: info)
            loginError = "Could not connect to \(failedServer). Your server may have changed. Enter a different server address below to reconnect."
        }
    }

    func signIn(serverURL: String, username: String, password: String) async {
        isAuthenticating = true
        loginError = nil
        defer { isAuthenticating = false }
        guard let url = URL(string: serverURL) else { loginError = "Invalid server URL."; return }
        let info = ClientInfo(deviceId: store.deviceId)
        let client = APIClient(baseURL: url, clientInfo: info)
        do {
            let session = try await client.login(username: username, password: password)
            try store.save(session)
            self.session = session
            self.api = client.authenticated(with: session)
            self.lastServerURL = serverURL
        } catch {
            loginError = error.localizedDescription
        }
    }

    func signOut() {
        store.clear()
        session = nil
        let info = ClientInfo(deviceId: store.deviceId)
        api = APIClient(baseURL: URL(string: lastServerURL) ?? URL(string: "http://localhost:8096")!,
                        clientInfo: info)
    }

    func makePlaybackConfig() -> PlaybackController.Config {
        PlaybackController.Config(
            mpvBinaryPath: mpvPathOverride.isEmpty ? nil : mpvPathOverride,
            configDir: mpvConfigDir,
            additionalConfigPath: MPVConfigurationStore.activeOverridePath
        )
    }
}
