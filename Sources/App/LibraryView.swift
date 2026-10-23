import SwiftUI
import JellyfinKit

struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    let parent: BaseItem

    @State private var items: [BaseItem] = []
    @State private var totalCount: Int?
    @State private var serverStartIndex = 0
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var recentSeriesLoaded = false
    @State private var generation = UUID()
    @State private var filterText = ""
    @AppStorage("solfin.librarySort") private var sortRaw = LibrarySort.name.rawValue
    @AppStorage("solfin.librarySortAscending") private var sortAscending = true
    @AppStorage("solfin.libraryPlayedFilter") private var playedFilterRaw = PlayedFilter.all.rawValue
    @AppStorage("solfin.libraryCardSize") private var cardSizeRaw = LibraryCardSize.small.rawValue
    @AppStorage("solfin.libraryCardType") private var cardTypeRaw = LibraryCardType.poster.rawValue

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
                        EmptyContentView(title: query.isEmpty && playedFilter == .all ? "Nothing here" : "No matching titles",
                                         message: query.isEmpty
                                         ? "Try changing the watched filter, or add titles to this library."
                                         : "No titles match \"\(query)\" in this library. Try another search or watched filter.",
                                         systemImage: query.isEmpty ? "film" : "magnifyingglass")
                    } else {
                        itemGrid
                        if hasMore {
                            Color.clear.frame(height: 1)
                                .onAppear { Task { await loadNextPage() } }
                                .id(serverStartIndex)
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
        .searchable(text: $filterText, placement: .toolbar, prompt: "Search \(parent.name.lowercased())")
        .task(id: "\(parent.id)-\(sort.rawValue)-\(sortAscending)-\(playedFilter.rawValue)-\(query)") {
            await reloadAndWait(debounce: !query.isEmpty)
        }
    }

    private var libraryHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                libraryHeading
                Spacer(minLength: 20)
                libraryControls
            }
            VStack(alignment: .leading, spacing: 16) {
                libraryHeading
                ScrollView(.horizontal, showsIndicators: false) {
                    libraryControls
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var libraryHeading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(parent.name)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            if let count = totalCount {
                Text(query.isEmpty ? "\(count) titles" : "\(count) results")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var libraryControls: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Watched", selection: playedFilterBinding) {
                    ForEach(PlayedFilter.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                toolbarMenuLabel(playedFilter.title, icon: "line.3.horizontal.decrease")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .modifier(LibraryToolbarControl(isActive: playedFilter != .all))
            .help("Filter by watched status")

            Menu {
                Section("Sort By") {
                    ForEach(availableSorts) { option in
                        Button { sortRaw = option.rawValue } label: {
                            if sort == option { Label(option.title(for: parent.collectionType), systemImage: "checkmark") }
                            else { Text(option.title(for: parent.collectionType)) }
                        }
                    }
                }
                Section("Order") {
                    Button { sortAscending = true } label: {
                        if sortAscending { Label(sortOrderTitle(ascending: true), systemImage: "checkmark") }
                        else { Text(sortOrderTitle(ascending: true)) }
                    }
                    Button { sortAscending = false } label: {
                        if !sortAscending { Label(sortOrderTitle(ascending: false), systemImage: "checkmark") }
                        else { Text(sortOrderTitle(ascending: false)) }
                    }
                }
            } label: {
                toolbarMenuLabel(sort.title(for: parent.collectionType), icon: sortAscending ? "arrow.up" : "arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .modifier(LibraryToolbarControl())
            .help("Sort by \(sort.title.lowercased()) · \(sortDirectionTitle.lowercased())")

            Menu {
                Section("Card type") {
                    Picker("Type", selection: cardTypeBinding) {
                        ForEach(LibraryCardType.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Card size") {
                    Picker("Size", selection: cardSizeBinding) {
                        ForEach(LibraryCardSize.allCases) { Text($0.title).tag($0) }
                    }
                }
            } label: {
                toolbarMenuLabel("\(cardType.title) · \(cardSize.title)", icon: "square.grid.2x2")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .modifier(LibraryToolbarControl())
            .help("Change card type and size")
            if playedFilter != .all || !query.isEmpty {
                Button {
                    filterText = ""
                    playedFilterRaw = PlayedFilter.all.rawValue
                } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain)
                .modifier(LibraryToolbarControl())
                .help("Clear search and watched filter")
                .accessibilityLabel("Clear search and watched filter")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(.white.opacity(0.9))
    }

    private func toolbarMenuLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
            Text(title)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.6)
        }
    }

    private var sortDirectionTitle: String { sortOrderTitle(ascending: sortAscending) }

    private func sortOrderTitle(ascending: Bool) -> String {
        switch sort {
        case .name: ascending ? "A to Z" : "Z to A"
        case .newest, .recentEpisodes, .releaseDate: ascending ? "Oldest first" : "Newest first"
        case .rating: ascending ? "Lowest rated first" : "Highest rated first"
        }
    }

    private var sort: LibrarySort {
        let stored = LibrarySort(rawValue: sortRaw) ?? .name
        return availableSorts.contains(stored) ? stored : .name
    }
    private var playedFilter: PlayedFilter { PlayedFilter(rawValue: playedFilterRaw) ?? .all }
    private var query: String { filterText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cardSize: LibraryCardSize { LibraryCardSize(rawValue: cardSizeRaw) ?? .small }
    private var cardType: LibraryCardType { LibraryCardType(rawValue: cardTypeRaw) ?? .poster }
    private var density: LibraryDensity { LibraryDensity(size: cardSize) }
    private var playedFilterBinding: Binding<PlayedFilter> {
        Binding(get: { playedFilter }, set: { playedFilterRaw = $0.rawValue })
    }
    private var cardSizeBinding: Binding<LibraryCardSize> {
        Binding(get: { cardSize }, set: { cardSizeRaw = $0.rawValue })
    }
    private var cardTypeBinding: Binding<LibraryCardType> {
        Binding(get: { cardType }, set: { cardTypeRaw = $0.rawValue })
    }
    @ViewBuilder
    private var itemGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: density.spacing) { itemLinks }
    }

    @ViewBuilder
    private var itemLinks: some View {
        ForEach(items) { item in
            LibraryItemCard(item: item, cardType: cardType, size: cardSize)
        }
    }

    private var columns: [GridItem] {
        let width: CGFloat
        switch cardType {
        case .poster: width = cardSize.posterWidth
        case .thumbnail: width = cardSize.thumbnailRowWidth
        case .banner: width = cardSize.bannerWidth
        }
        return [GridItem(.adaptive(minimum: width, maximum: width), spacing: density.spacing)]
    }

    private func reload() { Task { await reloadAndWait() } }
    private func reloadAndWait(debounce: Bool = false) async {
        let token = UUID(); generation = token
        items = []; totalCount = nil; serverStartIndex = 0; hasMore = true; recentSeriesLoaded = false; loadError = nil
        // A canceled request must not keep the next generation locked in loading.
        isLoading = true
        if debounce {
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
        }
        guard !Task.isCancelled, token == generation else { return }
        isLoading = false
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
                                                                               filters: playedFilter.apiValue,
                                                                               searchTerm: query)
                guard expected == generation, !Task.isCancelled else { return }
                items = activeSeries
                totalCount = items.count
                recentSeriesLoaded = true
                hasMore = false
            } else {
                let itemTypes: String?
                switch parent.collectionType?.lowercased() {
                case "movies": itemTypes = "Movie"
                case "tvshows": itemTypes = "Series"
                default: itemTypes = nil
                }
                let response = try await appState.api.items(
                    parentId: parent.id, startIndex: serverStartIndex, limit: pageSize,
                    sortBy: sort.apiValue, sortOrder: sortAscending ? "Ascending" : "Descending",
                    includeItemTypes: itemTypes, filters: playedFilter.apiValue, searchTerm: query)
                guard expected == generation, !Task.isCancelled else { return }
                let availableItems = response.items.filter(\.isBrowsableMedia)
                items.append(contentsOf: availableItems.filter { candidate in !items.contains(where: { $0.id == candidate.id }) })
                serverStartIndex += response.items.count
                totalCount = response.totalRecordCount
                hasMore = !response.items.isEmpty
                    && serverStartIndex < (response.totalRecordCount ?? Int.max)
            }
        } catch {
            guard expected == generation, !Task.isCancelled else { return }
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
            "Recently added"
        case .recentEpisodes: "Episode activity"
        case .releaseDate: "Release date"
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
    var title: String { switch self { case .all: "All titles"; case .unplayed: "Unwatched"; case .played: "Watched" } }
    var apiValue: String? { switch self { case .all: nil; case .unplayed: "IsUnplayed"; case .played: "IsPlayed" } }
}

enum LibraryCardType: String, CaseIterable, Identifiable {
    case poster, thumbnail, banner
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum LibraryCardSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var posterWidth: CGFloat { switch self { case .small: 160; case .medium: 200; case .large: 240 } }
    var titleFont: CGFloat { switch self { case .small: 17; case .medium: 18; case .large: 19 } }
    var subtitleFont: CGFloat { switch self { case .small, .medium: 14; case .large: 15 } }
    var spacing: CGFloat { switch self { case .small: 20; case .medium: 24; case .large: 28 } }
    var thumbnailWidth: CGFloat { switch self { case .small: 64; case .medium: 80; case .large: 96 } }
    var thumbnailHeight: CGFloat { thumbnailWidth * 1.5 }
    var thumbnailRowWidth: CGFloat { switch self { case .small: 360; case .medium: 460; case .large: 560 } }
    var bannerWidth: CGFloat { switch self { case .small: 300; case .medium: 420; case .large: 540 } }
    var bannerHeight: CGFloat { bannerWidth * 0.564 }
}

struct LibraryDensity {
    let size: LibraryCardSize
    var posterWidth: CGFloat { size.posterWidth }
    var minimumWidth: CGFloat { posterWidth }
    var maximumWidth: CGFloat { posterWidth }
    var spacing: CGFloat { size.spacing }
    var posterHeight: CGFloat { posterWidth * 1.5 }
    var titleFont: CGFloat { size.titleFont }
    var subtitleFont: CGFloat { size.subtitleFont }
}
