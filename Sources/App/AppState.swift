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
        }
    }

    var isSignedIn: Bool { session != nil }

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
