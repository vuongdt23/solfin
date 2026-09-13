import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("solfin")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text("Power-user Jellyfin client · external mpv")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                labeledField("Server", text: $server, prompt: "http://localhost:8096")
                labeledField("Username", text: $username, prompt: "user")
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 360)

            if let err = appState.loginError {
                Text(err).foregroundStyle(.red).font(.callout)
                    .frame(width: 360, alignment: .leading)
            }

            Button {
                Task { await appState.signIn(serverURL: server, username: username, password: password) }
            } label: {
                if appState.isAuthenticating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign In").frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isAuthenticating || server.isEmpty || username.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .onAppear { if server.isEmpty { server = appState.lastServerURL } }
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }
}
