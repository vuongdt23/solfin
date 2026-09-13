import SwiftUI
import JellyfinKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var nowPlaying: NowPlaying

    @State private var views: [BaseItem] = []
    @State private var resume: [BaseItem] = []
    @State private var nextUp: [BaseItem] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let err = loadError {
                        Text(err).foregroundStyle(.red)
                    }
                    if !resume.isEmpty { shelf("Continue Watching", resume) }
                    if !nextUp.isEmpty { shelf("Next Up", nextUp) }
                    ForEach(views) { view in
                        NavigationLink(value: view) {
                            HStack {
                                Text(view.name).font(.title2.bold())
                                Image(systemName: "chevron.right").font(.caption)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
            .navigationTitle("solfin")
            .navigationDestination(for: BaseItem.self) { destination(for: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Sign Out") { appState.signOut() }
                }
            }
            .safeAreaInset(edge: .bottom) { NowPlayingBar() }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func destination(for item: BaseItem) -> some View {
        // Series → seasons/episodes; libraries → grid; playable items → detail.
        if item.type == "Series" {
            SeriesDetailView(series: item)
        } else if item.collectionType != nil || item.type == "CollectionFolder" {
            LibraryView(parent: item)
        } else {
            ItemDetailView(itemId: item.id)
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, _ items: [BaseItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            async let v = appState.api.views()
            async let r = appState.api.resumeItems()
            async let n = appState.api.nextUp()
            views = try await v
            resume = (try? await r) ?? []
            nextUp = (try? await n) ?? []
        } catch {
            loadError = error.localizedDescription
        }
    }
}
