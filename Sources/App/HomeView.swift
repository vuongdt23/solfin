import SwiftUI
import JellyfinKit
import PlaybackEngine

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    let embeddedInShell: Bool

    @State private var views: [BaseItem] = []
    @State private var resume: [BaseItem] = []
    @State private var nextUp: [BaseItem] = []
    @State private var latestMovies: [BaseItem] = []
    @State private var latestShows: [BaseItem] = []
    @State private var showcase: [BaseItem] = []
    @State private var loadError: String?
    @State private var isLoading = true

    init(embeddedInShell: Bool = false) { self.embeddedInShell = embeddedInShell }

    var body: some View {
        Group {
            if embeddedInShell { content }
            else {
                NavigationStack {
                    content.navigationDestination(for: BaseItem.self) { destination(for: $0) }
                }
            }
        }
        .navigationTitle("Home")
        .task { await load() }
        .refreshable { await load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !featured.isEmpty { FeaturedMediaBar(items: featured) }
                // Give each shelf enough breathing room so the feature artwork and
                // the library/content areas read as distinct sections.
                VStack(alignment: .leading, spacing: 44) {
                    if isLoading && resume.isEmpty && nextUp.isEmpty { loadingShelves }
                    if !views.isEmpty { librariesSection }
                    if !resume.isEmpty { landscapeShelf("Continue Watching", resume) }
                    if !nextUp.isEmpty { landscapeShelf("Next Up", nextUp) }
                    if !latestShows.isEmpty { shelf("Recently Added in Shows", latestShows) }
                    if !latestMovies.isEmpty { shelf("Recently Added in Movies", latestMovies) }
                    if let loadError, resume.isEmpty && nextUp.isEmpty && latestMovies.isEmpty && latestShows.isEmpty {
                        EmptyContentView(title: "Home is unavailable", message: loadError,
                                         systemImage: "wifi.exclamationmark") { Task { await load() } }
                    }
                }
                .padding(.horizontal, SolfinDesign.pagePadding)
                // Let shelves begin inside the lower fade of the feature artwork,
                // avoiding a hard transition while keeping most of the artwork visible.
                .padding(.top, featured.isEmpty ? 22 : -76)
                .padding(.bottom, SolfinDesign.pagePadding)
            }
        }
        .background {
            ZStack {
                SolfinDesign.solarBackground
                RadialGradient(colors: [SolfinDesign.solarOrange.opacity(0.16), .clear],
                               center: UnitPoint(x: 0.96, y: 0.02), startRadius: 0, endRadius: 720)
                    .blendMode(.screen)
                RadialGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.14), .clear],
                               center: UnitPoint(x: 0.12, y: 0.88), startRadius: 60, endRadius: 900)
                    .blendMode(.screen)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var featured: [BaseItem] {
        var seen = Set<String>()
        return (showcase + latestMovies + latestShows + resume + nextUp).filter { item in
            guard item.backdropImageTags?.isEmpty == false else { return false }
            return seen.insert(item.id).inserted
        }.prefix(8).map { $0 }
    }

    private var loadingShelves: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.12)).frame(width: 190, height: 22)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: SolfinDesign.posterRadius)
                            .fill(.secondary.opacity(0.12)).frame(width: 160, height: 240)
                    }
                }
            }
        }.redacted(reason: .placeholder)
    }

    private var librariesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Libraries").font(.title.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(views) { view in
                        NavigationLink(value: view) { LibraryBanner(item: view) }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 4).padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private func destination(for item: BaseItem) -> some View {
        if item.type == "Series" { SeriesDetailView(series: item) }
        else if item.collectionType != nil || item.type == "CollectionFolder" { LibraryView(parent: item) }
        else { ItemDetailView(itemId: item.id) }
    }

    private func landscapeShelf(_ title: String, _ items: [BaseItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { LandscapeCard(item: item) }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 8).padding(.horizontal, 2)
            }
        }
    }

    private func shelf(_ title: String, _ items: [BaseItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { PosterCard(item: item) }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 8).padding(.horizontal, 2)
            }
        }
    }

    private func load() async {
        isLoading = true; loadError = nil
        async let viewsResult: Result<[BaseItem], Error> = capture { try await appState.api.views() }
        async let resumeResult: Result<[BaseItem], Error> = capture { try await appState.api.resumeItems() }
        async let nextResult: Result<[BaseItem], Error> = capture { try await appState.api.nextUp() }
        async let moviesResult: Result<[BaseItem], Error> = capture { try await appState.api.latestItems(includeItemTypes: "Movie") }
        async let showsResult: Result<[BaseItem], Error> = capture { try await appState.api.latestItems(includeItemTypes: "Series") }
        async let featuredResult: Result<[BaseItem], Error> = capture { try await appState.api.featuredItems() }
        let results = await (viewsResult, resumeResult, nextResult, moviesResult, showsResult, featuredResult)
        if case .success(let value) = results.0 { views = value }
        if case .success(let value) = results.1 { resume = value }
        if case .success(let value) = results.2 { nextUp = value }
        if case .success(let value) = results.3 { latestMovies = value }
        if case .success(let value) = results.4 { latestShows = value }
        if case .success(let value) = results.5 { showcase = value }
        let errors = [results.0, results.1, results.2, results.3, results.4, results.5].compactMap { result -> String? in
            if case .failure(let error) = result { return error.localizedDescription }
            return nil
        }
        loadError = errors.first
        isLoading = false
    }
}

private struct FeaturedTitle: View {
    let item: BaseItem

    var body: some View {
        SolarMediaLogo(item: item)
    }
}

private struct FeaturedPlayButtonStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .background(hovering ? Color.white.opacity(0.86) : .white, in: Capsule())
            .overlay { Capsule().strokeBorder(hovering || configuration.isPressed ? SolfinDesign.solarGold : .clear, lineWidth: configuration.isPressed ? 3 : 2) }
            .shadow(color: SolfinDesign.solarOrange.opacity(hovering || configuration.isPressed ? 0.42 : 0.16), radius: hovering ? 20 : 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : hovering ? 1.035 : 1)
    }
}

private struct FeaturedInfoButtonStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(hovering || configuration.isPressed ? SolfinDesign.solarOrange.opacity(0.72) : .white.opacity(0.22), in: Circle())
            .overlay { Circle().strokeBorder(hovering || configuration.isPressed ? SolfinDesign.solarGold : .white.opacity(0.2), lineWidth: hovering || configuration.isPressed ? 2 : 1) }
            .shadow(color: SolfinDesign.solarOrange.opacity(hovering || configuration.isPressed ? 0.48 : 0.12), radius: hovering ? 18 : 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.94 : hovering ? 1.08 : 1)
    }
}

private struct FeaturedCarouselButtonStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(hovering || configuration.isPressed ? SolfinDesign.solarOrange.opacity(0.78) : .black.opacity(0.5), in: Circle())
            .overlay { Circle().strokeBorder(hovering || configuration.isPressed ? SolfinDesign.solarGold : .white.opacity(0.14), lineWidth: hovering || configuration.isPressed ? 2 : 1) }
            .shadow(color: SolfinDesign.solarOrange.opacity(hovering || configuration.isPressed ? 0.48 : 0.16), radius: hovering ? 20 : 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.94 : hovering ? 1.12 : 1)
    }
}

private struct FeaturedPagerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

private struct FeaturedPlayButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
        }
        .buttonStyle(SolarPillButtonStyle(hovering: hovering))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .accessibilityLabel(title)
    }
}

private struct FeaturedInfoButton: View {
    let item: BaseItem
    @State private var hovering = false

    var body: some View {
        NavigationLink(value: item) {
            Image(systemName: "info")
                .font(.headline.weight(.semibold))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(SolarRoundButtonStyle(hovering: hovering))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .help("Open details")
        .accessibilityLabel("Open \(item.name)")
    }
}

private struct FeaturedCarouselButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(SolarRoundButtonStyle(hovering: hovering, idleFill: .black.opacity(0.5)))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FeaturedPagerDot: View {
    let index: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(.white.opacity(selected ? 1 : hovering ? 0.82 : 0.5))
                .frame(width: selected ? 22 : hovering ? 13 : 7, height: 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeaturedPagerButtonStyle())
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .accessibilityLabel("Featured item \(index + 1)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await operation()) }
    catch { return .failure(error) }
}

private struct FeaturedMediaBar: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("solfin.featuredAutoAdvance") private var autoAdvance = true
    let items: [BaseItem]
    @State private var selection = 0
    @State private var hovering = false

    private var item: BaseItem { items[min(selection, items.count - 1)] }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                NavigationLink(value: item) {
                    heroArtwork
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        // Cached images can retain their aspect-fit layout beyond the
                        // hero's bounds; clip it so an image edge never renders as a
                        // one-pixel rule at the bottom of the feature.
                        .clipped()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(item.id)
                .transition(.opacity)
                .accessibilityLabel("Open \(item.name)")
                .accessibilityHint("Shows media details")

                RadialGradient(colors: [SolfinDesign.solarGold.opacity(0.38), SolfinDesign.solarOrange.opacity(0.22), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 740)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                RadialGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.24), .clear],
                               center: .bottomLeading, startRadius: 20, endRadius: 820)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.08), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .allowsHitTesting(false)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.46),
                    .init(color: SolfinDesign.spaceBlack.opacity(0.20), location: 0.66),
                    .init(color: SolfinDesign.spaceBlack.opacity(0.76), location: 0.86),
                    .init(color: SolfinDesign.spaceBlack, location: 1.0)
                ], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                RadialGradient(colors: [SolfinDesign.solarOrange.opacity(0.14), SolfinDesign.solarRed.opacity(0.06), .clear],
                               center: UnitPoint(x: 0.76, y: 0.86), startRadius: 60, endRadius: 560)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                RadialGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.12), .clear],
                               center: UnitPoint(x: 0.26, y: 0.90), startRadius: 80, endRadius: 620)
                    .blendMode(.screen)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 28) {
                        // Separate the title treatment from its metadata and actions;
                        // the logo should have room to read before the info block begins.
                        VStack(alignment: .leading, spacing: 25) {
                            SolarHeroIdentity(
                                item: item,
                                runtime: runtime(item),
                                overview: item.overview
                            ) {
                                SolarHeroActions {
                                    FeaturedPlayButton(title: playLabel(item)) { playFeatured(item) }
                                    FeaturedInfoButton(item: item)
                                }
                            }
                        }
                        Spacer(minLength: 20)
                        HStack(spacing: 7) {
                            ForEach(items.indices, id: \.self) { index in
                                FeaturedPagerDot(index: index, selected: index == selection) {
                                    withAnimation(.easeInOut(duration: 0.45)) { selection = index }
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }.padding(.horizontal, 72).padding(.bottom, 118).padding(.top, 40)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)

                HStack {
                    carouselButton("chevron.left", action: previous)
                    Spacer()
                    carouselButton("chevron.right", action: next)
                }
                .padding(.horizontal, 12)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity)
        // Keep the feature artwork prominent without reserving an oversized block
        // above the homepage shelves.
        .containerRelativeFrame(.vertical, alignment: .top) { available, _ in max(700, available * 0.78) }
        .ignoresSafeArea(edges: .top)
        .onHover { hovering = $0 }
        .task(id: items.map(\.id).joined(separator: ",")) {
            // Warm the shared logo overlay cache for every item in the media bar so
            // starting playback from the homepage does not need a cold download.
            for item in items {
                await LogoOverlayCache.shared.prefetch(for: item, api: appState.api)
            }
        }
        .task(id: "\(selection)-\(hovering)-\(autoAdvance)") {
            guard autoAdvance, !reduceMotion, !hovering, items.count > 1 else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, !hovering else { return }
            withAnimation(.easeInOut(duration: 0.5)) { next() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured media")
    }

    @ViewBuilder private var heroArtwork: some View {
        if let url = appState.api.backdropImageURL(for: item, maxWidth: nil) {
            CachedImage(url: url)
        } else {
            LinearGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.45), SolfinDesign.spaceBlack],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func carouselButton(_ icon: String, action: @escaping () -> Void) -> some View {
        FeaturedCarouselButton(icon: icon,
                               help: icon == "chevron.left" ? "Previous feature" : "Next feature",
                               action: action)
    }
    private func runtime(_ item: BaseItem) -> String? {
        guard let ticks = item.runTimeTicks else { return nil }
        let minutes = Int(Ticks.toSeconds(ticks) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    private func playLabel(_ item: BaseItem) -> String { "Play" }
    private func playFeatured(_ item: BaseItem) {
        if item.type == "Series" {
            Task { await playSeries(item) }
        } else {
            play(item)
        }
    }
    private func playSeries(_ series: BaseItem) async {
        appState.playbackError = nil
        do {
            let episodes = try await appState.api.episodes(seriesId: series.id)
            guard let episode = episodes.first(where: { Ticks.toSeconds($0.userData?.playbackPositionTicks) > 0 })
                    ?? episodes.first(where: { $0.userData?.played != true })
                    ?? episodes.first else { return }
            nowPlaying.play(item: episode, api: appState.api, config: appState.makePlaybackConfig(),
                            queue: episodes, queueIndex: episodes.firstIndex(where: { $0.id == episode.id })) {
                appState.playbackError = $0
            }
        } catch {
            appState.playbackError = error.localizedDescription
        }
    }
    private func play(_ item: BaseItem) {
        appState.playbackError = nil
        nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig()) {
            appState.playbackError = $0
        }
    }
    private func next() { selection = (selection + 1) % items.count }
    private func previous() { selection = (selection - 1 + items.count) % items.count }
}
