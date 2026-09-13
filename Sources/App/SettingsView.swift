import SwiftUI
import PlaybackEngine

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("solfin.autoplayNext") private var autoplayNext = true
    @AppStorage("solfin.featuredAutoAdvance") private var featuredAutoAdvance = true
    @StateObject private var configStore = MPVConfigurationStore()
    @State private var validationMessage: String?

    var body: some View {
        TabView {
            Form {
                Section("Home") {
                    Toggle("Automatically advance featured media", isOn: $featuredAutoAdvance)
                    Text("The home feature uses a large cinematic backdrop with Solfin's solar dark theme.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Episodes") {
                    Toggle("Automatically play the next episode", isOn: $autoplayNext)
                }
            }
            .formStyle(.grouped).padding(12)
            .tabItem { Label("General", systemImage: "switch.2") }

            playbackSettings
                .tabItem { Label("Playback", systemImage: "play.rectangle") }

            MPVConfigurationView(store: configStore)
                .tabItem { Label("mpv Config", systemImage: "doc.text") }

            Form {
                LabeledContent("Server", value: appState.session?.serverURL.absoluteString ?? "Not connected")
                LabeledContent("User", value: appState.session?.userName ?? "—")
                Button("Sign Out", role: .destructive) { appState.signOut() }
            }
            .formStyle(.grouped).padding(12)
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(minWidth: 820, idealWidth: 960, minHeight: 560, idealHeight: 680)
        .onAppear { configStore.load(bundledConfigDir: appState.mpvConfigDir) }
    }

    private var playbackSettings: some View {
        Form {
            Section("mpv Executable") {
                TextField("Automatic detection", text: $appState.mpvPathOverride)
                HStack {
                    Button("Choose…", action: chooseMPV)
                    Button("Validate", action: validateMPV)
                    Button("Reset to Automatic") {
                        appState.mpvPathOverride = ""
                        validationMessage = nil
                    }
                }
                if let validationMessage {
                    Label(validationMessage, systemImage: validationMessage.hasPrefix("Ready")
                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(validationMessage.hasPrefix("Ready") ? .green : .red)
                }
            }
            Section("Playback Model") {
                LabeledContent("Streaming", value: "Original file · Direct play")
                LabeledContent("Configuration", value: configStore.overrideConfiguration
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Bundled defaults" : "Bundled defaults + custom overrides")
                Text("Configuration changes apply to the next playback session. An mpv process already running is not restarted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding(12)
    }

    private func chooseMPV() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose mpv"
        if panel.runModal() == .OK, let path = panel.url?.path {
            appState.mpvPathOverride = path
            validateMPV()
        }
    }

    private func validateMPV() {
        if let path = MPVProcess.locateBinary(override: appState.mpvPathOverride.isEmpty ? nil : appState.mpvPathOverride) {
            validationMessage = "Ready: \(path)"
        } else {
            validationMessage = "mpv was not found. Install it with Homebrew or choose the executable."
        }
    }
}

private struct MPVConfigurationView: View {
    @ObservedObject var store: MPVConfigurationStore
    @State private var showBundled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showBundled {
                HSplitView {
                    editorPane(title: "Bundled configuration", subtitle: "Read-only · shipped with Solfin",
                               text: .constant(store.bundledConfiguration), editable: false)
                    editorPane(title: "Your overrides", subtitle: "Loaded after bundled defaults",
                               text: $store.overrideConfiguration, editable: true)
                }
            } else {
                editorPane(title: "Your overrides", subtitle: "Loaded after bundled defaults",
                           text: $store.overrideConfiguration, editable: true)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("mpv Configuration").font(.title2.weight(.semibold))
                Text("Keep Solfin's tuned defaults and override only the options you want to change.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Show Bundled", isOn: $showBundled).toggleStyle(.switch)
        }.padding(20)
    }

    private func editorPane(title: String, subtitle: String, text: Binding<String>, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.headline)
                    if !editable {
                        Text("READ ONLY").font(.caption2.weight(.bold)).tracking(0.8)
                            .foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.secondary.opacity(0.1), in: Capsule())
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if editable {
                configEditor(text: text, editable: true)
            } else {
                // A disabled SwiftUI TextEditor also disables scrolling and selection.
                // Use an AppKit text view in read-only mode so bundled configuration
                // remains scrollable, selectable, and copyable.
                ReadOnlyConfigTextView(text: text.wrappedValue)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.72),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.7)) }
            }
        }
        .padding(16).frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func configEditor(text: Binding<String>, editable: Bool) -> some View {
        TextEditor(text: text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.7)) }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            status
            Spacer()
            Button("Reveal File") { store.revealInFinder() }
            Button("Clear") { store.clear() }.disabled(store.overrideConfiguration.isEmpty)
            Button("Revert") { store.revert() }.disabled(!store.hasUnsavedChanges)
            Button("Save Overrides") { store.save() }
                .buttonStyle(.borderedProminent)
                .disabled(!store.hasUnsavedChanges)
        }.padding(16)
    }

    @ViewBuilder private var status: some View {
        switch store.saveState {
        case .clean:
            Label("No unsaved changes", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .unsaved:
            Label("Unsaved changes", systemImage: "circle.fill").foregroundStyle(.orange)
        case .saved:
            Label("Saved · applies to new playback", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
