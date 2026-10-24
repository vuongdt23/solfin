import SwiftUI
import JellyfinKit

/// Hero remains in the shell so it can bleed edge-to-edge; its editorial body
/// has an independent composition and reserves the navigation rail.
struct CinematicHomeView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 42) { content() }
    }
}

struct WatchNowHomeView: View {
    let lead: BaseItem
    let supporting: [BaseItem]
    let resumeIDs: Set<String>
    let availableWidth: CGFloat

    private var context: String {
        resumeIDs.contains(lead.id) ? "Pick up where you left off" : lead.type == "Episode" ? "Your next episode" : "Start something tonight"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HomeSectionTitle(title: resumeIDs.contains(lead.id) ? "Welcome back." : "Tonight starts here.", eyebrow: context)
            if availableWidth >= 1000 && !supporting.isEmpty {
                HStack(alignment: .top, spacing: 22) {
                    leadTile(height: 540)
                        .frame(width: (availableWidth - 22) * 0.69)
                    supportingStack(height: supporting.count == 1 ? 540 : 259)
                }
            } else {
                leadTile(height: availableWidth < 650 ? 470 : 520)
                if !supporting.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: min(300, availableWidth)))], spacing: 18) {
                        ForEach(supporting) { item in
                            supportTile(item, height: 260)
                        }
                    }
                }
            }
        }
    }

    private func leadTile(height: CGFloat) -> some View {
        HomeFeatureArtwork(item: lead)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(lead.type == "Episode" ? lead.seriesName ?? lead.name : lead.name)
                        .font(.system(size: availableWidth < 650 ? 34 : 44, weight: .bold))
                        .tracking(-1.2)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let episode = HomePresentation.episodeIdentity(lead) {
                        Text(episode).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.88)).lineLimit(2)
                    }
                    if let overview = lead.overview {
                        Text(overview).font(.system(size: 15)).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                    }
                    HomeProgressIdentity(item: lead).frame(maxWidth: 380)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { actions }
                        VStack(alignment: .leading, spacing: 12) { actions }
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(availableWidth < 650 ? 24 : 36)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .cardHoverEffect(lift: 7, scale: 1.02)
    }

    @ViewBuilder private var actions: some View {
        HomePlaybackAction(item: lead, title: resumeIDs.contains(lead.id) ? "Resume watching" : "Play now")
        HomeDetailsAction(item: lead)
    }

    private func supportingStack(height: CGFloat) -> some View {
        VStack(spacing: 22) {
            ForEach(supporting) { item in supportTile(item, height: height) }
        }
    }

    private func supportTile(_ item: BaseItem, height: CGFloat) -> some View {
        HomeFeatureArtwork(item: item)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    SolarContextLabel(text: resumeIDs.contains(item.id) ? "Also in progress" : "Up next")
                    NavigationLink(value: item) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.seriesName ?? item.name).font(.system(size: 20, weight: .bold)).lineLimit(2)
                            if let episode = HomePresentation.episodeIdentity(item) {
                                Text(episode).font(.caption).foregroundStyle(.white.opacity(0.76)).lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Details for \(item.name)")
                    HomePlaybackAction(item: item, title: resumeIDs.contains(item.id) ? "Resume" : "Play episode")
                }
                .padding(20)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .cardHoverEffect(lift: 6, scale: 1.025)
    }
}

struct LibraryGalleryHomeView: View {
    let libraries: [BaseItem]
    let posters: [String: [BaseItem]]
    let availableWidth: CGFloat
    var artworkStyle: HomeLibraryArtworkStyle = .fan

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeSectionTitle(title: "Your collection.", eyebrow: "A world worth exploring")
            if availableWidth >= 1000 && libraries.count >= 3 {
                HStack(alignment: .top, spacing: 20) {
                    HomeLibraryTile(item: libraries[0], posters: posters[libraries[0].id] ?? [],
                                    width: (availableWidth - 20) * 0.6, tileHeight: 460, gallery: true, artworkStyle: artworkStyle)
                    VStack(spacing: 20) {
                        ForEach(Array(libraries.dropFirst().prefix(2))) { library in
                            HomeLibraryTile(item: library, posters: posters[library.id] ?? [],
                                            width: (availableWidth - 20) * 0.4, tileHeight: 220, gallery: true, artworkStyle: artworkStyle)
                        }
                    }
                }
                if libraries.count > 3 { grid(Array(libraries.dropFirst(3))) }
            } else {
                grid(libraries)
            }
        }
    }

    private func grid(_ items: [BaseItem]) -> some View {
        let columns = availableWidth >= 760 ? 2 : 1
        let width = (availableWidth - CGFloat(columns - 1) * 20) / CGFloat(columns)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columns), spacing: 20) {
            ForEach(items) { library in
                HomeLibraryTile(item: library, posters: posters[library.id] ?? [], width: width,
                                tileHeight: min(400, max(260, width * 0.62)), gallery: true, artworkStyle: artworkStyle)
            }
        }
    }
}
