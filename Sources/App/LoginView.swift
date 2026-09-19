import SwiftUI
import JellyfinKit

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var serverSplashURL: URL?
    @FocusState private var focusedField: Field?

    private enum Field { case server, username, password }

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
            if server.isEmpty { server = appState.lastServerURL }
            focusedField = .username
        }
        .onChange(of: server) { _, value in loadServerSplash(from: value) }
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
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: SolfinDesign.solarOrange.opacity(0.24), radius: 16, y: 6)
                Text("Welcome to Solfin").font(.system(size: 30, weight: .semibold)).tracking(-0.6)
                Text("Sign in to your Jellyfin server to browse and play your library.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 17) {
                input("Server address", prompt: "http://localhost:8096", text: $server, field: .server,
                      contentType: .URL)
                input("Username", prompt: "Your username", text: $username, field: .username,
                      contentType: .username)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Password").font(.callout.weight(.medium))
                    SecureField("Your password", text: $password)
                        .focused($focusedField, equals: .password)
                        .solarField()
                        .overlay { RoundedRectangle(cornerRadius: SolfinDesign.controlRadius).strokeBorder(focusedField == .password ? SolfinDesign.Control.borderFocused : SolfinDesign.Control.border, lineWidth: focusedField == .password ? 2 : 1) }
                        .textContentType(.password)
                }
            }

            if let error = appState.loginError {
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
                .font(.callout)
                .foregroundStyle(SolfinDesign.Control.textMuted)
            }

            Button(action: signIn) {
                HStack(spacing: 8) {
                    if appState.isAuthenticating { ProgressView().controlSize(.small) }
                    Text(appState.isAuthenticating ? "Connecting…" : "Continue")
                    if !appState.isAuthenticating { Image(systemName: "arrow.right") }
                }.frame(maxWidth: .infinity).frame(height: 28)
            }
            .buttonStyle(SolarPrimaryButtonStyle()).controlSize(.large)
            .disabled(appState.isAuthenticating || server.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(34).frame(width: 430)
        .glassSurface(cornerRadius: 26)
        .padding(.horizontal, 28)
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

    private func loadServerSplash(from value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil else {
            serverSplashURL = nil
            return
        }
        let client = APIClient(baseURL: url, clientInfo: ClientInfo(deviceId: UUID().uuidString))
        Task {
            do {
                _ = try await client.publicSystemInfo()
                guard !Task.isCancelled else { return }
                await MainActor.run { serverSplashURL = client.brandingSplashscreenURL() }
            } catch {
                await MainActor.run { serverSplashURL = nil }
            }
        }
    }

    private func signIn() {
        Task { await appState.signIn(serverURL: server.trimmingCharacters(in: .whitespacesAndNewlines),
                                     username: username, password: password) }
    }
}
