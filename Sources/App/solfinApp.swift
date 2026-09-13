import SwiftUI

@main
struct SolfinApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var nowPlaying = NowPlaying()

    init() {
        // Generous shared HTTP cache so poster/backdrop images load once and are
        // reused (Jellyfin serves images with ETags/long cache). Critical on slow
        // or tunneled links where refetching every scroll shows spinners.
        URLCache.shared = URLCache(memoryCapacity: 128 * 1024 * 1024,   // 128 MB RAM
                                   diskCapacity: 1024 * 1024 * 1024,     // 1 GB disk
                                   diskPath: "solfin-images")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(nowPlaying)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isSignedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
    }
}
