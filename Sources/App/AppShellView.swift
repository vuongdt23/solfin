import SwiftUI
import JellyfinKit

enum AppDestination: Hashable {
    case home
    case search
    case library(String)
}

struct AppShellView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    @State private var selection: AppDestination? = .home
    @State private var libraries: [BaseItem] = []
    @State private var searchText = ""
    @State private var detailPath: [BaseItem] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarExpanded = false

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack(path: $detailPath) {
                destinationView
                    .navigationDestination(for: BaseItem.self) { destination(for: $0) }
            }
            .background(SolfinDesign.solarBackground)
            .toolbarBackground(.hidden, for: .windowToolbar)

            IntegratedSolarSidebar(selection: detailPath.isEmpty ? selection : nil,
                                   libraries: libraries,
                                   isExpanded: $sidebarExpanded,
                                   navigate: navigate,
                                   icon: icon(for:))
                .zIndex(1)
        }
        .tint(SolfinDesign.solarOrange)
        .background(SolfinDesign.solarBackground)
        .preferredColorScheme(.dark)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .safeAreaPadding(.bottom, nowPlaying.isActive ? 82 : 0)
        .overlay(alignment: .center) {
            PlaybackLaunchOverlay()
        }
        .overlay(alignment: .bottom) {
            NowPlayingBar()
                .frame(maxWidth: 1180)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: nowPlaying.isActive)
        .task { await loadLibraries() }
        .onReceive(NotificationCenter.default.publisher(for: .solfinShowHome)) { _ in navigate(to: .home) }
        .onReceive(NotificationCenter.default.publisher(for: .solfinShowSearch)) { _ in navigate(to: .search) }
    }

    private func sidebarButton(_ title: String, systemImage: String,
                               destination: AppDestination) -> some View {
        Button { navigate(to: destination) } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selection == destination && detailPath.isEmpty
                           ? Color.accentColor.opacity(0.18) : Color.clear)
        .accessibilityAddTraits(selection == destination && detailPath.isEmpty ? .isSelected : [])
    }

    private func navigate(to destination: AppDestination) {
        detailPath.removeAll()
        selection = destination
    }

    @ViewBuilder
    private var destinationView: some View {
        switch selection ?? .home {
        case .home:
            HomeView(embeddedInShell: true)
        case .search:
            SearchView(searchText: $searchText)
        case .library(let id):
            if let library = libraries.first(where: { $0.id == id }) {
                LibraryView(parent: library)
                    .id(library.id)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func destination(for item: BaseItem) -> some View {
        if item.type == "Series" { SeriesDetailView(series: item) }
        else if item.collectionType != nil || item.type == "CollectionFolder" { LibraryView(parent: item) }
        else { ItemDetailView(itemId: item.id) }
    }

    private func loadLibraries() async {
        if let result = try? await appState.api.views() { libraries = result }
    }

    private func icon(for library: BaseItem) -> String {
        switch library.collectionType?.lowercased() {
        case "movies": return "film"
        case "tvshows": return "tv"
        default: return "rectangle.stack"
        }
    }
}

private struct PlaybackLaunchOverlay: View {
    @EnvironmentObject private var nowPlaying: NowPlaying

    var body: some View {
        if nowPlaying.isLaunching {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.24))
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    VStack(spacing: 4) {
                        Text("Starting mpv…")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        if let name = nowPlaying.itemName {
                            Text(name)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.16))
                }
                .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

extension Notification.Name {
    static let solfinShowHome = Notification.Name("solfin.showHome")
    static let solfinShowSearch = Notification.Name("solfin.showSearch")
}
