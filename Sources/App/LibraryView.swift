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
    @State private var recentSeriesLoaded = false
    @State private var generation = UUID()
    @State private var filterText = ""
    @AppStorage("solfin.librarySort") private var sortRaw = LibrarySort.name.rawValue
    @AppStorage("solfin.librarySortAscending") private var sortAscending = true
    @AppStorage("solfin.libraryPlayedFilter") private var playedFilterRaw = PlayedFilter.all.rawValue
    @AppStorage("solfin.libraryDensity") private var densityRaw = LibraryDensity.standard.rawValue

    private let pageSize = 60
    private var availableSorts: [LibrarySort] { LibrarySort.options(for: parent.collectionType) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                libraryHeader
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
                    } else if filteredItems.isEmpty {
                        EmptyContentView(title: "No matches",
                                         message: "No loaded titles match \"\(filterText.trimmingCharacters(in: .whitespacesAndNewlines))\".",
                                         systemImage: "magnifyingglass")
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: density.spacing) {
                            ForEach(filteredItems) { item in
                                NavigationLink(value: item) { PosterCard(item: item) }.buttonStyle(.plain)
                                    .onAppear { if item.id == items.last?.id { Task { await loadNextPage() } } }
                            }
                        }
                        if isLoading { ProgressView().controlSize(.small).padding(24).tint(SolfinDesign.solarOrange) }
                        if let loadError, !items.isEmpty {
                            VStack(spacing: 8) {
                                Text(loadError).font(.caption).foregroundStyle(.white.opacity(0.6))
                                Button("Retry") { Task { await loadNextPage() } }
                            }.frame(maxWidth: .infinity).padding(20)
                        }
                    }
                }
            }
            .padding(.horizontal, SolfinDesign.pagePadding)
            .padding(.top, 22)
            .padding(.bottom, SolfinDesign.pagePadding)
        }
        .background(SolfinDesign.solarBackground)
        .scrollContentBackground(.hidden)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .searchable(text: $filterText, placement: .toolbar, prompt: "Filter loaded titles")
        .task(id: "\(parent.id)-\(sort.rawValue)-\(sortAscending)-\(playedFilter.rawValue)") { await reloadAndWait() }
    }

    private var libraryHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(parent.name)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                if let count = totalCount {
                    Text(filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "\(count) items"
                         : "\(filteredItems.count) of \(count) items")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
            Spacer()
            Menu {
                Picker("Watched", selection: playedFilterBinding) {
                    ForEach(PlayedFilter.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label(playedFilter.title, systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(SolarToolbarButtonStyle())

            Menu {
                Section("Sort By") {
                    ForEach(availableSorts) { option in
                        Button { sortRaw = option.rawValue } label: {
                            if sort == option { Label(option.title(for: parent.collectionType), systemImage: "checkmark") }
                            else { Text(option.title(for: parent.collectionType)) }
                        }
                    }
                }
                Divider()
                Section("Direction") {
                    Button { sortAscending = true } label: {
                        if sortAscending { Label("Ascending", systemImage: "checkmark") }
                        else { Text("Ascending") }
                    }
                    Button { sortAscending = false } label: {
                        if !sortAscending { Label("Descending", systemImage: "checkmark") }
                        else { Text("Descending") }
                    }
                }
            } label: {
                Label("Sort", systemImage: sortAscending ? "arrow.up" : "arrow.down")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(SolarToolbarButtonStyle())

            Menu {
                Picker("Density", selection: densityBinding) {
                    ForEach(LibraryDensity.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("View", systemImage: "square.grid.3x3")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(SolarToolbarButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay { RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.28)) }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [SolfinDesign.solarOrange.opacity(0.24),
                                                              .white.opacity(0.08),
                                                              SolfinDesign.nebulaPurple.opacity(0.22)],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                }
        }
    }

    private var sort: LibrarySort {
        let stored = LibrarySort(rawValue: sortRaw) ?? .name
        return availableSorts.contains(stored) ? stored : .name
    }
    private var playedFilter: PlayedFilter { PlayedFilter(rawValue: playedFilterRaw) ?? .all }
    private var filteredItems: [BaseItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(query)
                || (item.seriesName?.localizedCaseInsensitiveContains(query) == true)
        }
    }
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
        items = []; totalCount = nil; hasMore = true; recentSeriesLoaded = false; loadError = nil
        await loadNextPage(token: token)
    }

    private func loadNextPage(token: UUID? = nil) async {
        let expected = token ?? generation
        guard !isLoading, hasMore, expected == generation else { return }
        isLoading = true; loadError = nil
        do {
            if sort == .recentEpisodes {
                guard !recentSeriesLoaded else { hasMore = false; isLoading = false; return }
                let activeSeries = try await appState.api.recentlyActiveSeries(parentId: parent.id,
                                                                               limit: nil,
                                                                               sortOrder: sortAscending ? "Ascending" : "Descending",
                                                                               filters: playedFilter.apiValue)
                guard expected == generation else { return }
                items = sortAscending ? Array(activeSeries.reversed()) : activeSeries
                totalCount = items.count
                recentSeriesLoaded = true
                hasMore = false
            } else {
                let response = try await appState.api.items(
                    parentId: parent.id, startIndex: items.count, limit: pageSize,
                    sortBy: sort.apiValue, sortOrder: sortAscending ? "Ascending" : "Descending",
                    filters: playedFilter.apiValue)
                guard expected == generation else { return }
                items.append(contentsOf: response.items.filter { candidate in !items.contains(where: { $0.id == candidate.id }) })
                totalCount = response.totalRecordCount
                hasMore = !response.items.isEmpty && items.count < (response.totalRecordCount ?? Int.max)
            }
        } catch {
            guard expected == generation else { return }
            loadError = error.localizedDescription
        }
        if expected == generation { isLoading = false }
    }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case name, newest, recentEpisodes, releaseDate, rating
    static func options(for collectionType: String?) -> [LibrarySort] {
        switch collectionType?.lowercased() {
        case "tvshows": return [.name, .newest, .recentEpisodes, .releaseDate, .rating]
        default: return [.name, .newest, .releaseDate, .rating]
        }
    }
    var id: String { rawValue }
    var title: String { title(for: nil) }
    func title(for collectionType: String?) -> String {
        switch self {
        case .name: "Title"
        case .newest:
            collectionType?.lowercased() == "movies" ? "Recently Added Movies" : "Recently Added Series"
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
