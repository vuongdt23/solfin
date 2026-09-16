import SwiftUI
import JellyfinKit
import PlaybackEngine

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("solfin.autoplayNext") private var autoplayNext = true
    @AppStorage("solfin.featuredAutoAdvance") private var featuredAutoAdvance = true
    @AppStorage(SolfinLog.levelKey) private var logLevelRaw = SolfinLogLevel.info.rawValue
    @AppStorage(SolfinLog.directoryKey) private var logDirectory = ""
    @StateObject private var configStore = MPVConfigurationStore()
    @State private var validationMessage: String?
    @State private var cacheStats = MediaAssetCache.Statistics(assetCount: 0, variantCount: 0, sourceBytes: 0, variantBytes: 0, location: "")
    @AppStorage("solfin.cacheMaxEntries") private var cacheMaxEntries = 500
    @AppStorage("solfin.cacheMaxMB") private var cacheMaxMB = 500
    @State private var cacheMessage: String?

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

            cacheSettings
                .tabItem { Label("Cache", systemImage: "externaldrive") }

            MPVConfigurationView(store: configStore)
                .tabItem { Label("mpv Config", systemImage: "doc.text") }

            loggingSettings
                .tabItem { Label("Logging", systemImage: "doc.badge.gearshape") }

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

    private var cacheSettings: some View {
        Form {
            Section("Overview") {
                LabeledContent("Cached images", value: "\(cacheStats.assetCount)")
                LabeledContent("BGRA variants", value: "\(cacheStats.variantCount)")
                LabeledContent("Source data", value: ByteCountFormatter.string(fromByteCount: cacheStats.sourceBytes, countStyle: .file))
                LabeledContent("BGRA data", value: ByteCountFormatter.string(fromByteCount: cacheStats.variantBytes, countStyle: .file))
                LabeledContent("Total", value: ByteCountFormatter.string(fromByteCount: cacheStats.totalBytes, countStyle: .file))
            }
            Section("Limits") {
                Picker("Maximum entries", selection: $cacheMaxEntries) {
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("250").tag(250)
                    Text("500").tag(500)
                    Text("1,000").tag(1_000)
                    Text("2,500").tag(2_500)
                    Text("5,000").tag(5_000)
                    Text("10,000").tag(10_000)
                    Text("Unlimited").tag(0)
                }
                .pickerStyle(.menu)
                Picker("Maximum size", selection: $cacheMaxMB) {
                    Text("50 MB").tag(50)
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1_000)
                    Text("2 GB").tag(2_000)
                    Text("5 GB").tag(5_000)
                    Text("Unlimited").tag(0)
                }
                .pickerStyle(.menu)
                Button("Run Cleanup") { runCacheCleanup() }
            }
            Section("Storage") {
                LabeledContent("Location", value: cacheStats.location).textSelection(.enabled)
                HStack {
                    Button("Refresh") { refreshCache() }
                    Button("Reveal in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: cacheStats.location)) }
                    Button("Clear Cache", role: .destructive) { clearCache() }
                }
                if let cacheMessage { Text(cacheMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped).padding(12)
        .task { refreshCache() }
    }

    private func refreshCache() {
        Task { cacheStats = await MediaAssetCache.shared.statistics() }
    }

    private func runCacheCleanup() {
        Task {
            let maxBytes = cacheMaxMB == 0 ? Int64.max : Int64(cacheMaxMB) * 1_024 * 1_024
            let maxEntries = cacheMaxEntries == 0 ? Int.max : cacheMaxEntries
            await MediaAssetCache.shared.cleanup(maxEntries: maxEntries, maxBytes: maxBytes)
            cacheMessage = "Cleanup completed."
            cacheStats = await MediaAssetCache.shared.statistics()
        }
    }

    private func clearCache() {
        Task {
            await MediaAssetCache.shared.clear()
            cacheMessage = "Cache cleared."
            cacheStats = await MediaAssetCache.shared.statistics()
        }
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

    private var loggingSettings: some View {
        Form {
            Section("Diagnostics") {
                Picker("Log level", selection: $logLevelRaw) {
                    ForEach(SolfinLogLevel.allCases) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Current file", value: SolfinLog.directoryURL.appendingPathComponent("solfin.log").path)
                    .textSelection(.enabled)

                Text("Logs include app, API latency, cache/logo latency, playback startup milestones, and mpv logs when enabled. Sensitive URL tokens are redacted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Location") {
                TextField(SolfinLog.defaultDirectoryPath, text: $logDirectory)
                    .textSelection(.enabled)
                HStack {
                    Button("Choose…", action: chooseLogDirectory)
                    Button("Reveal Logs", action: revealLogs)
                    Button("Reset to Default") { logDirectory = "" }
                }
                Text("Leave blank to use the default location: \(SolfinLog.defaultDirectoryPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("mpv") {
                LabeledContent("mpv log folder", value: SolfinLog.directoryURL.appendingPathComponent("mpv", isDirectory: true).path)
                    .textSelection(.enabled)
                Text("mpv receives --log-file and --msg-level matching the selected level for new playback sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding(12)
    }

    private func chooseLogDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use for Logs"
        if panel.runModal() == .OK, let path = panel.url?.path {
            logDirectory = path
        }
    }

    private func revealLogs() {
        let url = SolfinLog.directoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
