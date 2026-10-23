import SwiftUI

@main
struct SolfinApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var nowPlaying = NowPlaying()

    init() {
        URLCache.shared = URLCache(memoryCapacity: 128 * 1024 * 1024,
                                   diskCapacity: 1024 * 1024 * 1024,
                                   diskPath: "solfin-images")
    }

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(appState).environmentObject(nowPlaying)
                .preferredColorScheme(.dark)
                .background(SolfinDesign.solarBackground)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            SettingsView().environmentObject(appState).environmentObject(nowPlaying)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    var body: some View {
        Group {
            if appState.isSignedIn { AppShellView() }
            else { LoginView() }
        }
        .task { await appState.validateStoredSession() }
        .onDisappear { nowPlaying.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            nowPlaying.stop()
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isSignedIn)
    }
}
