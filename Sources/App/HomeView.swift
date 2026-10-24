import SwiftUI
import AppKit
import JellyfinKit
import PlaybackEngine

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    let embeddedInShell: Bool

    @StateObject private var data = HomeData()
    private var views: [BaseItem] { data.views }
    private var libraryPosters: [String: [BaseItem]] { data.libraryPosters }
    private var resume: [BaseItem] { data.resume }
    private var nextUp: [BaseItem] { data.nextUp }
    private var latestMovies: [BaseItem] { data.latestMovies }
    private var latestShows: [BaseItem] { data.latestShows }
    private var showcase: [BaseItem] { data.showcase }
    private var loadError: String? { data.loadError }
    private var isLoading: Bool { data.isLoading }
    @State private var recentFilter: HomeRecentFilter = .all
    @State private var isTopHovered = false
    @AppStorage("solfin.homeCardSize") private var cardSizeRaw = LibraryCardSize.small.rawValue
    @AppStorage("solfin.homeCardType") private var cardTypeRaw = LibraryCardType.poster.rawValue
    @AppStorage("solfin.homeLayout") private var layoutRaw = HomeLayout.cinematic.rawValue
    @AppStorage("solfin.homeHeroStyle") private var heroStyleRaw = HomeHeroStyle.full.rawValue

    private var layout: HomeLayout { HomeLayout.saved(layoutRaw) }
    private var heroStyle: HomeHeroStyle { HomeHeroStyle.saved(heroStyleRaw) }
    private var contentLeadingInset: CGFloat { max(contentHorizontalPadding, heroControlLeadingInset - 26) }

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
        .task(id: appState.session?.id) { await load() }
        .refreshable { await load() }
    }

    private var content: some View {
        GeometryReader { viewport in
            // The page scrolls vertically; each media shelf owns its own
            // horizontal scroll area so shelf width never changes the hero width.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if layout == .cinematic && !featured.isEmpty {
                        FeaturedMediaBar(items: featured,
                                         contentInset: contentHorizontalPadding,
                                         controlLeadingInset: heroControlLeadingInset,
                                         heroHeight: heroStyle == .spotlight ? 440 : max(460, min(1040, viewport.size.height * 0.78)),
                                         spotlight: heroStyle == .spotlight)
                    }
                    VStack(alignment: .leading, spacing: 32) {
                        if isLoading && resume.isEmpty && nextUp.isEmpty { loadingShelves }
                        modeComposition(availableWidth: HomeShelfGeometry.contentWidth(viewport: viewport.size.width,
                                                                                     leadingInset: contentLeadingInset))
                        if let loadError, !allContentEmpty {
                            HStack {
                                Label("Some home content could not be refreshed", systemImage: "wifi.exclamationmark")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Retry") { Task { await load() } }.buttonStyle(.plain)
                            }
                            .help(loadError)
                        }
                        if let loadError, allContentEmpty {
                            EmptyContentView(title: "Home is unavailable", message: loadError,
                                             systemImage: "wifi.exclamationmark") { Task { await load() } }
                        } else if !isLoading && allContentEmpty {
                            EmptyContentView(title: "Your home is ready", message: "Add media to your Jellyfin libraries to see it here.",
                                             systemImage: "film") { Task { await load() } }
                        }
                    }
                    .environment(\.homeShelfWidth, HomeShelfGeometry.contentWidth(viewport: viewport.size.width,
                                                                                leadingInset: contentLeadingInset))
                    .padding(.leading, contentLeadingInset)
                    .padding(.trailing, 32)
                    .padding(.top, layout == .cinematic && !featured.isEmpty ? 24 : 68)
                    .padding(.bottom, 48)
                    // Horizontal shelves scroll internally; constrain the page
                    // content to the window instead of its combined shelf width.
                    .frame(width: viewport.size.width, alignment: .leading)
                }
                .frame(width: viewport.size.width, alignment: .topLeading)
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topTrailing) {
                HomeLayoutMenu(layoutRaw: $layoutRaw, heroStyleRaw: $heroStyleRaw,
                               isTopHovered: isTopHovered)
                    .padding(.trailing, 32)
                    .padding(.top, 16)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): isTopHovered = location.y >= 0 && location.y <= 96
                case .ended: isTopHovered = false
                }
            }
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

    private var allContentEmpty: Bool {
        views.isEmpty && resume.isEmpty && nextUp.isEmpty && latestMovies.isEmpty && latestShows.isEmpty && featured.isEmpty
    }

    @ViewBuilder
    private func modeComposition(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 42) {
            switch layout {
            case .cinematic:
                CinematicHomeView {
                    if !resume.isEmpty { landscapeShelf("Continue Watching", resume, isResume: true, compact: true) }
                    if !nextUp.isEmpty { landscapeShelf("Next Up", nextUp, compact: true) }
                    if !featured.isEmpty {
                        editorialSection("Worth a closer look", items: Array(featured.dropFirst()), width: availableWidth,
                                         context: "From your library")
                    }
                    recentlyAddedShelves
                    if !views.isEmpty { librariesSection(availableWidth: availableWidth) }
                }
            case .watchNow:
                let selection = HomePresentation.watchSelection(resume: resume, nextUp: nextUp,
                                                                 discovery: showcase + latestMovies + latestShows)
                if let lead = selection.lead {
                    WatchNowHomeView(lead: lead, supporting: selection.supporting,
                                     resumeIDs: Set(resume.map(\.id)), availableWidth: availableWidth)
                    let selectedIDs = Set(([lead] + selection.supporting).map(\.id))
                    let otherResume = HomePresentation.unique(resume, excluding: selectedIDs)
                    let otherNext = HomePresentation.unique(nextUp, excluding: selectedIDs.union(otherResume.map(\.id)))
                    if !otherResume.isEmpty { landscapeShelf("Your other unfinished titles", otherResume, isResume: true) }
                    if !otherNext.isEmpty { landscapeShelf("More episodes ahead", otherNext) }
                    editorialSection("Something new to start",
                                     items: HomePresentation.unique(showcase + latestMovies + latestShows,
                                                                    excluding: selectedIDs.union(resume.map(\.id))),
                                     width: availableWidth, context: "Explore your library")
                }
                if !views.isEmpty && selection.lead == nil { LibraryGalleryHomeView(libraries: views, posters: libraryPosters, availableWidth: availableWidth) }
                recentlyAddedShelves
                if !views.isEmpty && selection.lead != nil { librariesSection(availableWidth: availableWidth) }
            case .library:
                if !views.isEmpty { LibraryGalleryHomeView(libraries: views, posters: libraryPosters, availableWidth: availableWidth) }
                recentCollection(availableWidth: availableWidth)
                watchingShelves
            }
        }
        .frame(width: availableWidth, alignment: .leading)
    }

    @ViewBuilder
    private func editorialSection(_ title: String, items: [BaseItem], width: CGFloat, context: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                HomeSectionTitle(title: title)
                HomeEditorialComposition(items: Array(HomePresentation.unique(items).prefix(3)),
                                         availableWidth: width, context: context)
            }
        }
    }

    @ViewBuilder
    private func recentCollection(availableWidth: CGFloat) -> some View {
        let filters: [HomeRecentFilter] = [.all] + (latestMovies.isEmpty ? [] : [.movies]) + (latestShows.isEmpty ? [] : [.shows])
        let effectiveFilter = filters.contains(recentFilter) ? recentFilter : .all
        let recent = HomePresentation.recent(movies: latestMovies, shows: latestShows, filter: effectiveFilter)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        HomeSectionTitle(title: "New in your collection")
                        Spacer()
                        recentFilters(filters, effective: effectiveFilter)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HomeSectionTitle(title: "New in your collection")
                        recentFilters(filters, effective: effectiveFilter)
                    }
                }
                HomeEditorialComposition(items: Array(recent.prefix(3)), availableWidth: availableWidth,
                                         context: "Recently added", posterSupport: true)
                if recent.count > 3 { shelf("More recent additions", Array(recent.dropFirst(3))) }
            }
        }
    }

    private func recentFilters(_ filters: [HomeRecentFilter], effective: HomeRecentFilter) -> some View {
        HStack(spacing: 6) {
            ForEach(filters) { filter in
                Button { recentFilter = filter } label: {
                    Text(filter.title).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .foregroundStyle(effective == filter ? .black : .white.opacity(0.7))
                        .background(effective == filter ? .white : .white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter recent additions: \(filter.title)")
                .accessibilityAddTraits(effective == filter ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var watchingShelves: some View {
        if !resume.isEmpty { landscapeShelf("Continue Watching", resume, isResume: true) }
        if !nextUp.isEmpty { landscapeShelf("Next Up", nextUp) }
    }

    @ViewBuilder
    private var recentlyAddedShelves: some View {
        if !latestShows.isEmpty { shelf("Recently Added in Shows", latestShows) }
        if !latestMovies.isEmpty { shelf("Recently Added in Movies", latestMovies) }
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

    private func landscapeShelf(_ title: String, _ items: [BaseItem], isResume: Bool = false, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(title, detail: isResume ? "Pick up where you left off" : nil)
            HorizontalWheelScrollView {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        // Continue Watching and Next Up keep their dedicated wide card style,
                        // independent of the library/home card preference.
                        NavigationLink(value: item) {
                            LandscapeCard(item: item, size: compact ? .small : .medium,
                                          showResumeDetails: isResume)
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

    private func load() async { await data.load(appState: appState) }
}

private struct FeaturedPagerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
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

/// Horizontal SwiftUI scroll views on macOS respond to horizontal wheel deltas,
/// but a typical vertical mouse wheel does not move them. Translate wheel input
/// over each shelf into horizontal scrolling without affecting other page areas.
private struct HorizontalWheelScrollView<Content: View>: View {
    @Environment(\.homeShelfWidth) private var shelfWidth
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            content()
        }
        .frame(width: shelfWidth, alignment: .leading)
        .overlay {
            HomeShelfWheelObserver().allowsHitTesting(false)
        }
    }
}

private struct FeaturedMediaBar: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("solfin.featuredAutoAdvance") private var autoAdvance = true
    let items: [BaseItem]
    let contentInset: CGFloat
    let controlLeadingInset: CGFloat
    let heroHeight: CGFloat
    var spotlight = false
    @State private var selection = 0
    @State private var hovering = false

    private var leadingInset: CGFloat { max(contentInset, controlLeadingInset - 26) }

    private var item: BaseItem { items[min(selection, items.count - 1)] }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 580
            let expansive = proxy.size.width > 1600
            let splitSpotlight = spotlight && proxy.size.width - leadingInset > 760
            let spotlightArtworkWidth = max(0, proxy.size.width - leadingInset - 32) * 0.52
            let textWidth = splitSpotlight
                ? min(480, (proxy.size.width - leadingInset) * 0.44)
                : min(expansive ? 680 : 560, max(0, proxy.size.width - leadingInset - 40))

            // The fixed canvas owns layout; oversized fill images live only in
            // overlays, so their intrinsic dimensions cannot enlarge the hero.
            SolfinDesign.spaceBlack
                .overlay {
                    NavigationLink(value: item) {
                        if splitSpotlight {
                            Color.clear
                                .overlay(alignment: .trailing) {
                                    heroArtwork(size: CGSize(width: spotlightArtworkWidth, height: proxy.size.height - 52))
                                        .frame(width: spotlightArtworkWidth, height: proxy.size.height - 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                        .padding(.trailing, 32)
                                        .mask {
                                            LinearGradient(colors: [.clear, .black, .black],
                                                           startPoint: .leading, endPoint: .trailing)
                                        }
                                }
                                .contentShape(Rectangle())
                        } else {
                            heroArtwork(size: proxy.size)
                                .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .id(item.id)
                    .transition(.opacity)
                    .accessibilityLabel("Open \(item.name)")
                    .accessibilityHint("Shows media details")
                }
                .overlay {
                    LinearGradient(stops: [
                        .init(color: SolfinDesign.spaceBlack.opacity(splitSpotlight ? 0 : 0.76), location: 0),
                        .init(color: SolfinDesign.spaceBlack.opacity(splitSpotlight ? 0 : 0.42), location: 0.28),
                        .init(color: SolfinDesign.spaceBlack.opacity(splitSpotlight ? 0 : 0.08), location: 0.58),
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
                    .opacity(splitSpotlight ? 0 : 1)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                        HStack(spacing: 12) {
                            Capsule().fill(SolfinDesign.solarGold).frame(width: 28, height: 2)
                            SolarContextLabel(text: "Featured in your library")
                        }
                        SolarMediaLogo(item: item, maxWidth: min(expansive ? 620 : 520, textWidth),
                                       height: spotlight ? 80 : compact ? 100 : expansive ? 200 : 160,
                                       fallbackSize: spotlight ? 40 : compact ? 48 : expansive ? 80 : 64)
                        SolarMediaMetadata(item: item, runtime: runtime(item))
                        if !compact, let genres = item.genres { SolarGenreRow(genres: genres) }
                        if let overview = item.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: spotlight ? 16 : expansive ? 22 : 19, weight: .medium))
                                .lineSpacing(5)
                                .foregroundStyle(.white.opacity(0.84))
                                .lineLimit(compact ? 2 : 3)
                                .frame(maxWidth: textWidth, alignment: .leading)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { heroActions }
                            VStack(alignment: .leading, spacing: 12) { heroActions }
                        }
                        .padding(.top, 4)
                    }
                    .frame(width: textWidth, alignment: .leading)
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 3)
                    .padding(.leading, leadingInset)
                    .padding(.bottom, compact ? 64 : 88)
                }
                .overlay(alignment: .bottomTrailing) {
                    if items.count > 1 {
                        HStack(spacing: 14) {
                            if proxy.size.width - leadingInset > 900 {
                                HStack(spacing: 0) {
                                    ForEach(items.indices, id: \.self) { index in
                                        FeaturedPagerDot(index: index, selected: index == selection) {
                                            select(index)
                                        }
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
                        .opacity(spotlight || hovering ? 1 : 0)
                        .allowsHitTesting(spotlight || hovering)
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
            selection = min(selection, items.count - 1)
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
        .task(id: "\(selection)-\(hovering)-\(autoAdvance)-\(reduceMotion)-\(items.map(\.id).joined(separator: ","))") {
            guard autoAdvance, !reduceMotion, !hovering, items.count > 1 else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, !hovering else { return }
            next()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured media")
    }

    @ViewBuilder private var heroActions: some View {
        HomePlaybackAction(item: item, title: HomePresentation.progress(item) != nil ? "Resume" : "Play",
                           prominent: !spotlight)
        HomeDetailsAction(item: item, prominent: !spotlight)
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
    private func select(_ index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { selection = index }
    }
    private func next() { select((selection + 1) % items.count) }
    private func previous() { select((selection - 1 + items.count) % items.count) }
}
