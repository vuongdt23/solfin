import SwiftUI
import JellyfinKit

/// Owns the refresh lifecycle independently of mode views and lazy tile lifetimes.
/// Layout switches never reload data or randomize the collection artwork.
@MainActor
final class HomeData: ObservableObject {
    @Published private(set) var views: [BaseItem] = []
    @Published private(set) var libraryPosters: [String: [BaseItem]] = [:]
    @Published private(set) var resume: [BaseItem] = []
    @Published private(set) var nextUp: [BaseItem] = []
    @Published private(set) var latestMovies: [BaseItem] = []
    @Published private(set) var latestShows: [BaseItem] = []
    @Published private(set) var showcase: [BaseItem] = []
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = true
    private var refreshID = UUID()
    private var sessionID: String?

    func load(appState: AppState) async {
        let api = appState.api
        let currentSession = appState.session?.id
        if sessionID != currentSession {
            views = []; libraryPosters = [:]; resume = []; nextUp = []
            latestMovies = []; latestShows = []; showcase = []
            sessionID = currentSession
        }
        let requestID = UUID()
        refreshID = requestID
        isLoading = true
        loadError = nil
        async let viewsResult = capture { try await api.views() }
        async let resumeResult = capture { try await api.resumeItems() }
        async let nextResult = capture { try await api.nextUp() }
        async let moviesResult = capture { try await api.latestItems(includeItemTypes: "Movie") }
        async let showsResult = capture { try await api.latestItems(includeItemTypes: "Series") }
        async let featuredResult = capture { try await api.featuredItems() }
        let results = await [viewsResult, resumeResult, nextResult, moviesResult, showsResult, featuredResult]
        guard refreshID == requestID, appState.session?.id == currentSession else { return }
        if case .success(let value) = results[0] { views = value }
        if case .success(let value) = results[1] { resume = HomePresentation.unique(value) }
        if case .success(let value) = results[2] { nextUp = HomePresentation.unique(value) }
        if case .success(let value) = results[3] { latestMovies = HomePresentation.unique(value) }
        if case .success(let value) = results[4] { latestShows = HomePresentation.unique(value) }
        if case .success(let value) = results[5] { showcase = HomePresentation.unique(value) }
        loadError = results.compactMap { result -> String? in
            if case .failure(let error) = result { return error.localizedDescription }
            return nil
        }.first
        isLoading = false
        guard !Task.isCancelled else { return }

        let history = appState.libraryPosterHistory
        await withTaskGroup(of: (String, [BaseItem]?).self) { group in
            for library in views {
                let previous = history["\(currentSession ?? "")-\(library.id)"] ?? []
                group.addTask {
                    (library.id, try? await api.libraryPosterItems(for: library, excluding: previous))
                }
            }
            for await (id, posters) in group {
                guard !Task.isCancelled, refreshID == requestID,
                      appState.session?.id == currentSession else { continue }
                if let posters {
                    libraryPosters[id] = posters
                    appState.libraryPosterHistory["\(currentSession ?? "")-\(id)"] = posters.map(\.id)
                }
                // Preserve the previous collage if this decorative request fails.
            }
        }
    }

    private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
}
