import SwiftUI
import JellyfinKit

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var serverSplashURL: URL?
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var validatedServerURL: String?
    @State private var validationTask: Task<Void, Never>?
    @State private var stage: Stage = .server
    @FocusState private var focusedField: Field?

    private enum Stage: Equatable { case server, credentials }
    private enum Field { case server, username, password }
    private enum ConnectionStatus: Equatable {
        case idle, checking, connected, failed(String)
    }

    var body: some View {
        ZStack {
            atmosphericBackground
            VStack(spacing: 0) {
                Spacer(minLength: 44)
                signInPanel
                Spacer(minLength: 30)
                Text("Direct play through mpv")
                    .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 22)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            if server.isEmpty { server = appState.serverToReauthenticate?.serverURL.absoluteString ?? appState.lastServerURL }
            if let retry = appState.serverToReauthenticate {
                username = retry.userName
                stage = .credentials
            }
            focusedField = stage == .server ? .server : .username
            if stage == .credentials { validateServer() }
        }
        .onChange(of: appState.isAddingServer) { _, adding in
            if adding {
                if let retry = appState.serverToReauthenticate {
                    server = retry.serverURL.absoluteString
                    username = retry.userName
                    stage = .credentials
                    validateServer()
                } else {
                    stage = .server
                    focusedField = .server
                }
            }
        }
        .onChange(of: server) { _, _ in
            validationTask?.cancel()
            connectionStatus = .idle
            validatedServerURL = nil
            serverSplashURL = nil
            if stage == .credentials, appState.serverToReauthenticate != nil {
                Task {
                    await Task.yield()
                    validateServer()
                }
            }
        }
        .onDisappear { validationTask?.cancel() }
    }

    private var atmosphericBackground: some View {
        ZStack {
            if let serverSplashURL {
                CachedImage(url: serverSplashURL, contentMode: .fill)
                    .overlay { Color.black.opacity(0.58) }
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
            RadialGradient(colors: [SolfinDesign.solarOrange.opacity(colorScheme == .dark ? 0.22 : 0.12), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 620)
            RadialGradient(colors: [SolfinDesign.nebulaPurple.opacity(colorScheme == .dark ? 0.14 : 0.06), .clear],
                           center: .bottomTrailing, startRadius: 40, endRadius: 560)
            VStack {
                HStack {
                    Circle().fill(.white.opacity(0.05)).frame(width: 300, height: 300).blur(radius: 2)
                        .offset(x: -90, y: -110)
                    Spacer()
                }
                Spacer()
            }
        }.ignoresSafeArea()
    }

    private var signInPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            if stage == .server, !appState.savedSessions.isEmpty, !appState.isAddingServer {
                savedServers
            }

            VStack(alignment: .leading, spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().scaledToFit().frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: SolfinDesign.solarOrange.opacity(0.24), radius: 16, y: 6)
                Text(stage == .server ? "Connect to your server" : "Sign in")
                    .font(.system(size: 30, weight: .semibold)).tracking(-0.6)
                Text(stage == .server
                     ? "Enter your Jellyfin server address. Solfin will check the connection before continuing."
                     : "Sign in to \(URL(string: server)?.host ?? server) to browse and play your library.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if let retry = appState.serverToReauthenticate, stage == .credentials {
                Label("The saved credentials for \(retry.serverURL.host ?? retry.serverURL.absoluteString) were rejected. Sign in again to update them.",
                      systemImage: "key.horizontal")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if stage == .server {
                if appState.isAddingServer, appState.serverToReauthenticate == nil, !appState.savedSessions.isEmpty {
                    Button { appState.cancelAddingServer() } label: {
                        Label("Back to saved servers", systemImage: "chevron.left").font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                serverAddressForm
            } else {
                credentialsForm
            }

            if let error = appState.loginError, stage == .credentials {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error).textSelection(.enabled)
                }
                .font(.callout).foregroundStyle(.red)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if appState.isValidatingStoredSession {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to your server…")
                }
                .font(.callout).foregroundStyle(SolfinDesign.Control.textMuted)
            }

            if stage == .server {
                Button(action: validateServer) {
                    HStack(spacing: 8) {
                        if connectionStatus == .checking { ProgressView().controlSize(.small) }
                        Text(connectionButtonTitle)
                        if connectionStatus != .checking { Image(systemName: "arrow.right") }
                    }.frame(maxWidth: .infinity).frame(height: 28)
                }
                .buttonStyle(SolarPrimaryButtonStyle()).controlSize(.large)
                .disabled(connectionStatus == .checking || !isValidServerAddress)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(action: signIn) {
                    HStack(spacing: 8) {
                        if appState.isAuthenticating { ProgressView().controlSize(.small) }
                        Text(appState.isAuthenticating ? "Signing in…" : "Sign In")
                        if !appState.isAuthenticating { Image(systemName: "arrow.right") }
                    }.frame(maxWidth: .infinity).frame(height: 28)
                }
                .buttonStyle(SolarPrimaryButtonStyle()).controlSize(.large)
                .disabled(appState.isAuthenticating || username.isEmpty || password.isEmpty
                          || validatedServerURL != normalizedInput(server))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(34).frame(width: 430)
        .glassSurface(cornerRadius: 26)
        .padding(.horizontal, 28)
    }

    private var serverAddressForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            input("Server address", prompt: "http://localhost:8096", text: $server,
                  field: .server, contentType: .URL)
            switch connectionStatus {
            case .idle: EmptyView()
            case .checking:
                Label("Checking for Jellyfin…", systemImage: "network")
                    .foregroundStyle(.secondary)
            case .connected:
                Label("Jellyfin server found", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label(URL(string: server)?.host ?? server, systemImage: "server.rack")
                    .font(.callout.weight(.medium)).lineLimit(1)
                Spacer()
                Button("Change") {
                    stage = .server
                    password = ""
                    appState.loginError = nil
                    focusedField = .server
                }
                .buttonStyle(.plain).font(.caption)
            }
            input("Username", prompt: "Your username", text: $username,
                  field: .username, contentType: .username)
            VStack(alignment: .leading, spacing: 7) {
                Text("Password").font(.callout.weight(.medium))
                SecureField("Your password", text: $password)
                    .focused($focusedField, equals: .password)
                    .solarField()
                    .overlay { RoundedRectangle(cornerRadius: SolfinDesign.controlRadius).strokeBorder(focusedField == .password ? SolfinDesign.Control.borderFocused : SolfinDesign.Control.border, lineWidth: focusedField == .password ? 2 : 1) }
                    .textContentType(.password)
            }
        }
        .onAppear { focusedField = .username }
    }

    private var isValidServerAddress: Bool {
        guard let url = URL(string: normalizedInput(server)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil else { return false }
        return true
    }

    private var connectionButtonTitle: String {
        switch connectionStatus {
        case .checking: "Checking…"
        case .connected: "Continue"
        case .failed: "Try Again"
        case .idle: "Find Server"
        }
    }

    private func normalizedInput(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var savedServers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVED SERVERS").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
            ForEach(appState.savedSessions) { saved in
                HStack(spacing: 8) {
                    Button {
                        Task { await appState.switchServer(to: saved) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SolfinDesign.solarGold).frame(width: 34, height: 34)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(saved.serverURL.host ?? saved.serverURL.absoluteString).font(.callout.weight(.semibold))
                                Text(saved.userName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if appState.isAuthenticating { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                        }
                        .padding(11)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isAuthenticating)
                    Button(role: .destructive) { appState.removeServer(saved) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary).frame(width: 30, height: 44)
                    }
                    .buttonStyle(.plain).help("Forget this server")
                }
            }
            if appState.isAddingServer {
                Button { appState.cancelAddingServer() } label: {
                    Label("Back to saved servers", systemImage: "chevron.left").font(.caption.weight(.medium))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    private func input(_ label: String, prompt: String, text: Binding<String>, field: Field,
                       contentType: NSTextContentType?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.callout.weight(.medium))
            TextField(prompt, text: text)
                .focused($focusedField, equals: field)
                .solarField()
                .overlay { RoundedRectangle(cornerRadius: SolfinDesign.controlRadius).strokeBorder(focusedField == field ? SolfinDesign.Control.borderFocused : SolfinDesign.Control.border, lineWidth: focusedField == field ? 2 : 1) }
                .textContentType(contentType).autocorrectionDisabled()
        }
    }

    private func validateServer() {
        validationTask?.cancel()
        let address = normalizedInput(server)
        guard isValidServerAddress, let url = URL(string: address) else {
            connectionStatus = .failed("Enter a valid HTTP or HTTPS server address.")
            validatedServerURL = nil
            return
        }

        connectionStatus = .checking
        validatedServerURL = nil
        serverSplashURL = nil
        appState.loginError = nil
        let client = APIClient(baseURL: url, clientInfo: ClientInfo(deviceId: UUID().uuidString))
        validationTask = Task {
            do {
                _ = try await client.publicSystemInfo()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    validatedServerURL = address
                    connectionStatus = .connected
                    serverSplashURL = client.brandingSplashscreenURL()
                    stage = .credentials
                    focusedField = .username
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    validatedServerURL = nil
                    connectionStatus = .failed("Could not find a Jellyfin server at this address: \(error.localizedDescription)")
                }
            }
        }
    }

    private func signIn() {
        Task { await appState.signIn(serverURL: server.trimmingCharacters(in: .whitespacesAndNewlines),
                                     username: username, password: password) }
    }
}
