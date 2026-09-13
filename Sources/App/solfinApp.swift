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
    var body: some View {
        Group {
            if appState.isSignedIn { AppShellView() }
            else { LoginView() }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isSignedIn)
    }
}
