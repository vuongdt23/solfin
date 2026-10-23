import SwiftUI
import AppKit
import JellyfinKit
import PlaybackEngine

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    let embeddedInShell: Bool

    @State private var views: [BaseItem] = []
    @State private var libraryPosters: [String: [BaseItem]] = [:]
    @State private var libraryArtworkReload = UUID()
    @State private var resume: [BaseItem] = []
    @State private var nextUp: [BaseItem] = []
    @State private var latestMovies: [BaseItem] = []
    @State private var latestShows: [BaseItem] = []
    @State private var showcase: [BaseItem] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @AppStorage("solfin.homeCardSize") private var cardSizeRaw = LibraryCardSize.small.rawValue
    @AppStorage("solfin.homeCardType") private var cardTypeRaw = LibraryCardType.poster.rawValue

    private var cardSize: LibraryCardSize { LibraryCardSize(rawValue: cardSizeRaw) ?? .small }
    private var cardType: LibraryCardType { LibraryCardType(rawValue: cardTypeRaw) ?? .poster }

    /// The shell keeps the hero artwork edge-to-edge, while the content below it
    /// aligns to the usable area beside the floating navigation rail.
    init(embeddedInShell: Bool = false, heroControlLeadingInset: CGFloat? = nil) {
        self.embeddedInShell = embeddedInShell
        self.contentHorizontalPadding = embeddedInShell ? 82 : SolfinDesign.pagePadding
        self.heroControlLeadingInset = heroControlLeadingInset ?? (embeddedInShell ? 108 : 28)
    }

    private let contentHorizontalPadding: CGFloat
    private let heroControlLeadingInset: CGFloat

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
        .task(id: libraryArtworkReload) { await loadLibraryPosters() }
        .refreshable { await load() }
    }

    private var content: some View {
        GeometryReader { viewport in
            // The page scrolls vertically; each media shelf owns its own
            // horizontal scroll area so shelf width never changes the hero width.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if !featured.isEmpty {
                        FeaturedMediaBar(items: featured,
                                         contentInset: contentHorizontalPadding,
                                         controlLeadingInset: heroControlLeadingInset,
                                         heroHeight: max(460, min(1040, viewport.size.height * 0.78)))
                    }
                    VStack(alignment: .leading, spacing: 32) {
                        if isLoading && resume.isEmpty && nextUp.isEmpty { loadingShelves }
                        if !resume.isEmpty { landscapeShelf("Continue Watching", resume, isResume: true) }
                        if !nextUp.isEmpty { landscapeShelf("Next Up", nextUp) }
                        if !views.isEmpty {
                            librariesSection(availableWidth: viewport.size.width
                                             - max(contentHorizontalPadding, heroControlLeadingInset - 26) - 32)
                        }
                        if !latestShows.isEmpty { shelf("Recently Added in Shows", latestShows) }
                        if !latestMovies.isEmpty { shelf("Recently Added in Movies", latestMovies) }
                        if let loadError, resume.isEmpty && nextUp.isEmpty && latestMovies.isEmpty && latestShows.isEmpty {
                            EmptyContentView(title: "Home is unavailable", message: loadError,
                                             systemImage: "wifi.exclamationmark") { Task { await load() } }
                        }
                    }
                    .padding(.leading, max(contentHorizontalPadding, heroControlLeadingInset - 26))
                    .padding(.trailing, 32)
                    .padding(.top, featured.isEmpty ? 32 : 24)
                    .padding(.bottom, 48)
                    // Horizontal shelves scroll internally; constrain the page
                    // content to the window instead of its combined shelf width.
                    .frame(width: viewport.size.width, alignment: .leading)
                }
                .frame(width: viewport.size.width, alignment: .topLeading)
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            .scrollContentBackground(.hidden)
        }
        .background {
            ZStack {
                SolfinDesign.spaceBlack
                RadialGradient(colors: [SolfinDesign.nebulaPurple.opacity(0.08), .clear],
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
        }.prefix(20).map { $0 }
    }

    private var loadingShelves: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.12)).frame(width: 190, height: 22)
            HorizontalWheelScrollView {
                HStack(spacing: 18) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: SolfinDesign.posterRadius)
                            .fill(.secondary.opacity(0.12)).frame(width: 160, height: 240)
                    }
                }
            }
        }.redacted(reason: .placeholder)
    }

    private func librariesSection(availableWidth: CGFloat) -> some View {
        // Two substantial collection cards fit typical windows; ultrawide
        // windows cap their size rather than stretching the artwork endlessly.
        let tileWidth = min(560, max(380, (availableWidth - 26) / 2))
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Your Libraries", detail: "Browse all")
            HorizontalWheelScrollView {
                LazyHStack(spacing: 22) {
                    ForEach(views) { view in
                        HomeLibraryTile(item: view, posters: libraryPosters[view.id] ?? [], width: tileWidth)
                    }
                }.padding(.vertical, 8).padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private func destination(for item: BaseItem) -> some View {
        if item.type == "Series" { SeriesDetailView(series: item) }
        else if item.collectionType != nil || item.type == "CollectionFolder" { LibraryView(parent: item) }
        else { ItemDetailView(itemId: item.id) }
    }

    private func landscapeShelf(_ title: String, _ items: [BaseItem], isResume: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(title, detail: isResume ? "Pick up where you left off" : nil)
            HorizontalWheelScrollView {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        // Continue Watching and Next Up keep their dedicated wide card style,
                        // independent of the library/home card preference.
                        NavigationLink(value: item) {
                            LandscapeCard(item: item, showResumeDetails: isResume)
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 8).padding(.horizontal, 2)
            }
        }
    }

    private func shelf(_ title: String, _ items: [BaseItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(title)
            HorizontalWheelScrollView {
                LazyHStack(spacing: 18) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { homeCard(item) }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 8).padding(.horizontal, 2)
            }
        }
    }

    private func sectionHeading(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            if let detail {
                Text(detail.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func homeCard(_ item: BaseItem) -> some View {
        switch cardType {
        case .poster:
            PosterCard(item: item, size: LibraryDensity(size: cardSize))
        case .thumbnail:
            LandscapeCard(item: item, size: cardSize, useThumbnailArtwork: true)
        case .banner:
            LandscapeCard(item: item, size: cardSize)
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
        // Home owns the refresh cycle, not lazy tile lifetimes. Scrolling away
        // and back must not change artwork, but a new Home load should.
        libraryArtworkReload = UUID()
    }

    private func loadLibraryPosters() async {
        let api = appState.api
        let sessionID = appState.session?.id ?? ""
        let history = appState.libraryPosterHistory
        await withTaskGroup(of: (String, [BaseItem]?).self) { group in
            for library in views {
                let key = "\(sessionID)-\(library.id)"
                let previous = history[key] ?? []
                group.addTask {
                    let posters = try? await api.libraryPosterItems(for: library, excluding: previous)
                    return (library.id, posters)
                }
            }
            for await (id, posters) in group {
                guard !Task.isCancelled, appState.session?.id == api.session?.id else { continue }
                if let posters {
                    libraryPosters[id] = posters
                    appState.libraryPosterHistory["\(sessionID)-\(id)"] = posters.map(\.id)
                }
                // Preserve the previous stack if this decorative request fails.
            }
        }
    }
}

private struct FeaturedDetailsButtonStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(.white.opacity(hovering || configuration.isPressed ? 0.24 : 0.12), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(hovering ? 0.55 : 0.24)) }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
                .font(.system(size: 17, weight: .bold))
                .padding(.horizontal, 28)
                .frame(height: 52)
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
            Label("Details", systemImage: "info.circle")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 22)
                .frame(height: 52)
        }
        .buttonStyle(FeaturedDetailsButtonStyle(hovering: hovering))
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
                .frame(width: selected ? 24 : 6, height: 6)
                .frame(width: selected ? 28 : 18, height: 32)
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

/// Horizontal SwiftUI scroll views on macOS respond to horizontal wheel deltas,
/// but a typical vertical mouse wheel does not move them. Translate wheel input
/// over each shelf into horizontal scrolling without affecting other page areas.
private struct HorizontalWheelScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
        }
        .overlay {
            ShelfScrollWheelObserver()
                .allowsHitTesting(false)
        }
    }
}

private struct ShelfScrollWheelObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> ShelfScrollWheelView {
        ShelfScrollWheelView()
    }

    func updateNSView(_ view: ShelfScrollWheelView, context: Context) {}
}

private final class ShelfScrollWheelView: NSView {
    private var eventMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard let window else { return }
        installMonitor(for: window)
    }

    private func installMonitor(for window: NSWindow) {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak window] event in
            guard let self, let window, self.window === window,
                  event.window === window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: window.contentView)),
                  let contentView = window.contentView else {
                return event
            }

            // Find the actual horizontal shelf scroll view under the wheel
            // location. SwiftUI overlays aren't guaranteed to be descendants
            // of the NSScrollView they visually cover.
            let point = contentView.convert(event.locationInWindow, from: nil)
            var hitView = contentView.hitTest(point)
            var shelfScrollView: NSScrollView?
            while let view = hitView {
                if let scrollView = view as? NSScrollView,
                   let documentView = scrollView.documentView,
                   documentView.frame.width > scrollView.contentView.bounds.width + 1 {
                    shelfScrollView = scrollView
                    break
                }
                hitView = view.superview
            }
            guard let scrollView = shelfScrollView,
                  let documentView = scrollView.documentView else { return event }

            // Use horizontal wheel movement when present, otherwise map the
            // normal vertical wheel/trackpad gesture onto the shelf's x-axis.
            let delta = abs(event.scrollingDeltaX) > 0.1
                ? event.scrollingDeltaX : event.scrollingDeltaY
            guard abs(delta) > 0.1 else { return event }

            let clipView = scrollView.contentView
            let maxX = max(0, documentView.frame.width - clipView.bounds.width)
            let targetX = min(max(clipView.bounds.origin.x - delta, 0), maxX)
            guard abs(targetX - clipView.bounds.origin.x) > 0.1 else { return event }
            clipView.scroll(to: NSPoint(x: targetX, y: clipView.bounds.origin.y))
            scrollView.reflectScrolledClipView(clipView)
            return nil
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

private struct FeaturedMediaBar: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nowPlaying: NowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("solfin.featuredAutoAdvance") private var autoAdvance = true
    let items: [BaseItem]
    let contentInset: CGFloat
    let controlLeadingInset: CGFloat
    let heroHeight: CGFloat
    @State private var selection = 0
    @State private var hovering = false

    private var leadingInset: CGFloat { max(contentInset, controlLeadingInset - 26) }

    private var item: BaseItem { items[min(selection, items.count - 1)] }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 580
            let expansive = proxy.size.width > 1600
            let textWidth = min(expansive ? 680 : 560, proxy.size.width - leadingInset - 40)

            // The fixed canvas owns layout; oversized fill images live only in
            // overlays, so their intrinsic dimensions cannot enlarge the hero.
            SolfinDesign.spaceBlack
                .overlay {
                    NavigationLink(value: item) {
                        heroArtwork(size: proxy.size)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id(item.id)
                    .transition(.opacity)
                    .accessibilityLabel("Open \(item.name)")
                    .accessibilityHint("Shows media details")
                }
                .overlay {
                    LinearGradient(stops: [
                        .init(color: SolfinDesign.spaceBlack.opacity(0.76), location: 0),
                        .init(color: SolfinDesign.spaceBlack.opacity(0.42), location: 0.28),
                        .init(color: SolfinDesign.spaceBlack.opacity(0.08), location: 0.58),
                        .init(color: .clear, location: 0.8)
                    ], startPoint: .leading, endPoint: .trailing)
                    .allowsHitTesting(false)
                }
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: SolfinDesign.spaceBlack.opacity(0.48), location: 0.7),
                        .init(color: SolfinDesign.spaceBlack, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                        HStack(spacing: 12) {
                            Capsule().fill(SolfinDesign.solarGold).frame(width: 28, height: 2)
                            SolarContextLabel(text: "Featured in your library")
                        }
                        SolarMediaLogo(item: item, maxWidth: min(expansive ? 620 : 520, textWidth),
                                       height: compact ? 100 : expansive ? 200 : 160,
                                       fallbackSize: compact ? 48 : expansive ? 80 : 64)
                        SolarMediaMetadata(item: item, runtime: runtime(item))
                        if !compact, let genres = item.genres { SolarGenreRow(genres: genres) }
                        if let overview = item.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: expansive ? 22 : 19, weight: .medium))
                                .lineSpacing(5)
                                .foregroundStyle(.white.opacity(0.84))
                                .lineLimit(compact ? 2 : 3)
                                .frame(maxWidth: textWidth, alignment: .leading)
                        }
                        SolarHeroActions {
                            FeaturedPlayButton(title: playLabel(item)) { playFeatured(item) }
                            FeaturedInfoButton(item: item)
                        }
                        .padding(.top, 4)
                    }
                    .frame(width: textWidth, alignment: .leading)
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 3)
                    .padding(.leading, leadingInset)
                    .padding(.bottom, compact ? 64 : 88)
                }
                .overlay {
                    CarouselScrollWheelObserver { direction in
                        if direction > 0 { next() } else { previous() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomTrailing) {
                    if items.count > 1 {
                        HStack(spacing: 14) {
                            HStack(spacing: 0) {
                                ForEach(items.indices, id: \.self) { index in
                                    FeaturedPagerDot(index: index, selected: index == selection) {
                                        select(index)
                                    }
                                }
                            }
                            Text(String(format: "%02d / %02d", selection + 1, items.count))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.78))
                            carouselButton("chevron.left", action: previous)
                            carouselButton("chevron.right", action: next)
                        }
                        .padding(.trailing, 32)
                        .padding(.bottom, 20)
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(hovering)
                        .animation(.easeOut(duration: 0.18), value: hovering)
                    }
                }
                .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .ignoresSafeArea(edges: .top)
        .onHover { hovering = $0 }
        .task(id: items.map(\.id).joined(separator: ",")) {
            // Warm logos and local face analysis for subsequent carousel slides,
            // so both playback and artwork framing can use their shared caches.
            for item in items {
                await LogoOverlayCache.shared.prefetch(for: item, api: appState.api)
                guard !Task.isCancelled else { return }
                if let url = appState.api.backdropImageURL(for: item, maxWidth: nil) {
                    _ = await ArtworkFaceCache.shared.analysis(for: url)
                }
            }
        }
        .task(id: "\(selection)-\(hovering)-\(autoAdvance)") {
            guard autoAdvance, !reduceMotion, !hovering, items.count > 1 else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, !hovering else { return }
            next()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured media")
    }

    private func heroArtwork(size: CGSize) -> some View {
        let url = appState.api.backdropImageURL(for: item, maxWidth: nil)
        return FaceAwareHeroArtwork(url: url, size: size)
    }

    private func carouselButton(_ icon: String, action: @escaping () -> Void) -> some View {
        FeaturedCarouselButton(icon: icon,
                               help: icon == "chevron.left" ? "Previous feature" : "Next feature",
                               action: action)
    }
    private func runtime(_ item: BaseItem) -> String? {
        guard let ticks = item.runTimeTicks, ticks >= Ticks.perSecond * 60 else { return nil }
        let minutes = Int(Ticks.toSeconds(ticks) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    private func playLabel(_ item: BaseItem) -> String {
        Ticks.toSeconds(item.userData?.playbackPositionTicks) > 0 ? "Resume" : "Play"
    }
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
    private func select(_ index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { selection = index }
    }
    private func next() { select((selection + 1) % items.count) }
    private func previous() { select((selection - 1 + items.count) % items.count) }
}

/// Observes wheel gestures over the featured hero without placing an input-blocking
/// view over its buttons and navigation link.
private struct CarouselScrollWheelObserver: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> CarouselScrollWheelView {
        let view = CarouselScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CarouselScrollWheelView, context: Context) {
        view.onScroll = onScroll
    }
}

private final class CarouselScrollWheelView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var eventMonitor: Any?
    private var lastAdvance = Date.distantPast

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Keep mouse clicks routed to the artwork, play buttons, and carousel controls.
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: window.contentView)) else {
                return event
            }

            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            guard abs(delta) > 0.1 else { return nil }

            let now = Date()
            if now.timeIntervalSince(self.lastAdvance) >= 0.35 {
                self.lastAdvance = now
                self.onScroll?(delta)
            }
            // A wheel gesture over the hero is carousel input, not page scrolling.
            return nil
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}
