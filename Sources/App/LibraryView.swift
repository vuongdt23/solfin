import SwiftUI
import JellyfinKit

struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    let parent: BaseItem

    @State private var items: [BaseItem] = []
    @State private var totalCount: Int?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var generation = UUID()
    @AppStorage("solfin.librarySort") private var sortRaw = LibrarySort.name.rawValue
    @AppStorage("solfin.librarySortAscending") private var sortAscending = true
    @AppStorage("solfin.libraryPlayedFilter") private var playedFilterRaw = PlayedFilter.all.rawValue
    @AppStorage("solfin.libraryDensity") private var densityRaw = LibraryDensity.standard.rawValue

    private let pageSize = 60

    var body: some View {
        ScrollView {
            Group {
                if isLoading && items.isEmpty {
                    LoadingPosterGrid()
                } else if let loadError, items.isEmpty {
                    EmptyContentView(title: "Library unavailable", message: loadError,
                                     systemImage: "wifi.exclamationmark") { reload() }
                } else if items.isEmpty {
                    EmptyContentView(title: playedFilter == .all ? "Nothing here" : "No matching titles",
                                     message: playedFilter == .all
                                     ? "This library does not contain supported video items."
                                     : "Try changing the watched filter.")
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: density.spacing) {
                        ForEach(items) { item in
                            NavigationLink(value: item) { PosterCard(item: item) }.buttonStyle(.plain)
                                .onAppear { if item.id == items.last?.id { Task { await loadNextPage() } } }
                        }
                    }
                    if isLoading { ProgressView().controlSize(.small).padding(24) }
                    if let loadError, !items.isEmpty {
                        VStack(spacing: 8) {
                            Text(loadError).font(.caption).foregroundStyle(.secondary)
                            Button("Retry") { Task { await loadNextPage() } }
                        }.frame(maxWidth: .infinity).padding(20)
                    }
                }
            }
            .padding(SolfinDesign.pagePadding)
        }
        .navigationTitle(parent.name)
        .toolbar {
            ToolbarItemGroup {
                if let count = totalCount { Text("\(count) items").foregroundStyle(.secondary) }
                Menu {
                    Picker("Watched", selection: playedFilterBinding) {
                        ForEach(PlayedFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Label(playedFilter.title, systemImage: "line.3.horizontal.decrease.circle") }
                Menu {
                    Picker("Sort By", selection: sortBinding) {
                        ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Picker("Direction", selection: $sortAscending) {
                        Label("Ascending", systemImage: "arrow.up").tag(true)
                        Label("Descending", systemImage: "arrow.down").tag(false)
                    }
                } label: { Label("Sort", systemImage: sortAscending ? "arrow.up" : "arrow.down") }
                Menu {
                    Picker("Density", selection: densityBinding) {
                        ForEach(LibraryDensity.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Label("View", systemImage: "square.grid.3x3") }
            }
        }
        .task(id: "\(sort.rawValue)-\(sortAscending)-\(playedFilter.rawValue)") { await reloadAndWait() }
    }

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .name }
    private var playedFilter: PlayedFilter { PlayedFilter(rawValue: playedFilterRaw) ?? .all }
    private var density: LibraryDensity { LibraryDensity(rawValue: densityRaw) ?? .standard }
    private var sortBinding: Binding<LibrarySort> {
        Binding(get: { sort }, set: { sortRaw = $0.rawValue })
    }
    private var playedFilterBinding: Binding<PlayedFilter> {
        Binding(get: { playedFilter }, set: { playedFilterRaw = $0.rawValue })
    }
    private var densityBinding: Binding<LibraryDensity> {
        Binding(get: { density }, set: { densityRaw = $0.rawValue })
    }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: density.minimumWidth, maximum: density.maximumWidth), spacing: density.spacing)]
    }

    private func reload() { Task { await reloadAndWait() } }
    private func reloadAndWait() async {
        let token = UUID(); generation = token
        items = []; totalCount = nil; hasMore = true; loadError = nil
        await loadNextPage(token: token)
    }

    private func loadNextPage(token: UUID? = nil) async {
        let expected = token ?? generation
        guard !isLoading, hasMore, expected == generation else { return }
        isLoading = true; loadError = nil
        do {
            let response = try await appState.api.items(
                parentId: parent.id, startIndex: items.count, limit: pageSize,
                sortBy: sort.apiValue, sortOrder: sortAscending ? "Ascending" : "Descending",
                includeItemTypes: sort == .recentEpisodes ? "Episode" : nil,
                recursive: sort == .recentEpisodes, filters: playedFilter.apiValue)
            guard expected == generation else { return }
            items.append(contentsOf: response.items.filter { candidate in !items.contains(where: { $0.id == candidate.id }) })
            totalCount = response.totalRecordCount
            hasMore = !response.items.isEmpty && items.count < (response.totalRecordCount ?? Int.max)
        } catch {
            guard expected == generation else { return }
            loadError = error.localizedDescription
        }
        if expected == generation { isLoading = false }
    }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case name, newest, recentEpisodes, releaseDate, rating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Title"
        case .newest: "Recently Added"
        case .recentEpisodes: "Recently Added Episodes"
        case .releaseDate: "Release Date"
        case .rating: "Rating"
        }
    }
    var apiValue: String {
        switch self {
        case .name: "SortName"
        case .newest, .recentEpisodes: "DateCreated"
        case .releaseDate: "ProductionYear"
        case .rating: "CommunityRating"
        }
    }
}

private enum PlayedFilter: String, CaseIterable, Identifiable {
    case all, unplayed, played
    var id: String { rawValue }
    var title: String { switch self { case .all: "All"; case .unplayed: "Unplayed"; case .played: "Played" } }
    var apiValue: String? { switch self { case .all: nil; case .unplayed: "IsUnplayed"; case .played: "IsPlayed" } }
}

enum LibraryDensity: String, CaseIterable, Identifiable {
    case comfortable, standard, compact
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var minimumWidth: CGFloat { switch self { case .comfortable: 180; case .standard: 150; case .compact: 125 } }
    var maximumWidth: CGFloat { switch self { case .comfortable: 220; case .standard: 190; case .compact: 155 } }
    var spacing: CGFloat { switch self { case .comfortable: 26; case .standard: 20; case .compact: 14 } }
}
