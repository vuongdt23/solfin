import SwiftUI
import JellyfinKit

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var searchText: String
    @State private var results: [BaseItem] = []
    @State private var scope = SearchScope.all
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            Group {
                if searchText.trimmingCharacters(in: .whitespaces).count < 2 {
                    EmptyContentView(title: "Search your library", message: "Find movies, series, and episodes by title.", systemImage: "magnifyingglass")
                } else if isLoading && results.isEmpty {
                    LoadingPosterGrid()
                } else if let error, results.isEmpty {
                    EmptyContentView(title: "Search unavailable", message: error, systemImage: "wifi.exclamationmark") { scheduleSearch(immediate: true) }
                } else if results.isEmpty {
                    EmptyContentView(title: "No results", message: "Try another title or a different media type.", systemImage: "film.stack")
                } else {
                    VStack(alignment: .leading, spacing: 34) {
                        if scope == .all {
                            resultSection("Movies", items: movies)
                            resultSection("Series", items: series)
                            episodeSection
                        } else if scope == .episodes {
                            episodeSection
                        } else {
                            resultSection(scope.title, items: results)
                        }
                    }
                }
            }.padding(SolfinDesign.pagePadding)
        }
        .navigationTitle("Search")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Movies, series, episodes")
        .toolbar {
            ToolbarItem {
                Picker("Type", selection: $scope) { ForEach(SearchScope.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 310)
            }
        }
        .onChange(of: searchText) { _, _ in scheduleSearch() }
        .onChange(of: scope) { _, _ in scheduleSearch(immediate: true) }
        .onDisappear { searchTask?.cancel() }
    }

    private var movies: [BaseItem] { results.filter { $0.type == "Movie" } }
    private var series: [BaseItem] { results.filter { $0.type == "Series" } }
    private var episodes: [BaseItem] { results.filter { $0.type == "Episode" } }

    @ViewBuilder private func resultSection(_ title: String, items: [BaseItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.title2.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20)], alignment: .leading, spacing: 24) {
                    ForEach(items) { item in NavigationLink(value: item) { PosterCard(item: item) }.buttonStyle(.plain) }
                }
            }
        }
    }

    @ViewBuilder private var episodeSection: some View {
        if !episodes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Episodes").font(.title2.weight(.semibold))
                LazyVStack(spacing: 0) {
                    ForEach(episodes) { episode in
                        NavigationLink(value: episode) {
                            SearchEpisodeRow(episode: episode)
                        }.buttonStyle(.plain)
                        Divider().opacity(0.45)
                    }
                }
            }
        }
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { results = []; error = nil; isLoading = false; return }
        searchTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await MainActor.run { isLoading = true; error = nil }
            do {
                let response = try await appState.api.searchItems(term: term, includeItemTypes: scope.apiTypes)
                guard !Task.isCancelled, term == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                await MainActor.run { results = response.items; isLoading = false }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { self.error = error.localizedDescription; isLoading = false }
            }
        }
    }
}

private enum SearchScope: String, CaseIterable, Identifiable {
    case all, movies, series, episodes
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var apiTypes: String {
        switch self { case .all: "Movie,Series,Episode"; case .movies: "Movie"; case .series: "Series"; case .episodes: "Episode" }
    }
}

private struct SearchEpisodeRow: View {
    @EnvironmentObject private var appState: AppState
    let episode: BaseItem
    var body: some View {
        HStack(spacing: 14) {
            PosterImage(url: appState.api.primaryImageURL(for: episode, maxHeight: 180))
                .frame(width: 160, height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(episode.name).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                if let overview = episode.overview { Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.padding(.vertical, 12).contentShape(Rectangle())
    }
    private var subtitle: String {
        let s = episode.parentIndexNumber.map { "S\($0)" } ?? ""
        let e = episode.indexNumber.map { "E\($0)" } ?? ""
        return [episode.seriesName, s + e].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
