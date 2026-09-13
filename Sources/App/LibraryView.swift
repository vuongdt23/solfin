import SwiftUI
import JellyfinKit

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    let parent: BaseItem

    @State private var items: [BaseItem] = []
    @State private var loadError: String?
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            if let err = loadError {
                Text(err).foregroundStyle(.red).padding()
            }
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        PosterCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            if isLoading { ProgressView().padding() }
        }
        .navigationTitle(parent.name)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Series → episodes are nested under seasons; for v1 we recurse to episodes.
            let types = parent.type == "Series" ? "Episode" : nil
            let resp = try await appState.api.items(parentId: parent.id, limit: 200,
                                                    includeItemTypes: types)
            items = resp.items
        } catch {
            loadError = error.localizedDescription
        }
    }
}
