import Foundation
import JellyfinKit
import PlaybackEngine

/// Pure selection policy shared by the compositions and their regression tests.
enum HomePresentation {
    static func unique(_ items: [BaseItem], excluding ids: Set<String> = []) -> [BaseItem] {
        var seen = ids
        return items.filter { !$0.isOffline && seen.insert($0.id).inserted }
    }

    static func watchSelection(resume: [BaseItem], nextUp: [BaseItem], discovery: [BaseItem]) -> (lead: BaseItem?, supporting: [BaseItem]) {
        let availableResume = unique(resume)
        let lead = availableResume.first ?? unique(nextUp).first ?? unique(discovery).first
        guard let lead else { return (nil, []) }
        let supporting = unique(nextUp + availableResume, excluding: [lead.id])
        return (lead, Array(supporting.prefix(2)))
    }

    static func recent(movies: [BaseItem], shows: [BaseItem], filter: HomeRecentFilter) -> [BaseItem] {
        let items: [BaseItem]
        switch filter {
        case .all: items = movies + shows
        case .movies: items = movies
        case .shows: items = shows
        }
        // ISO date strings sort chronologically; preserve server order on ties.
        return unique(items).enumerated().sorted {
            let lhs = $0.element.dateCreated ?? ""
            let rhs = $1.element.dateCreated ?? ""
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.map(\.element)
    }

    static func progress(_ item: BaseItem) -> Double? {
        let duration = Ticks.toSeconds(item.runTimeTicks)
        let position = Ticks.toSeconds(item.userData?.playbackPositionTicks)
        if duration > 0 && position > 0 { return min(1, position / duration) }
        guard let percent = item.userData?.playedPercentage, percent > 0 else { return nil }
        return min(1, percent / 100)
    }

    static func remaining(_ item: BaseItem) -> String? {
        let duration = Ticks.toSeconds(item.runTimeTicks)
        guard duration > 0, let progress = progress(item), progress < 1 else { return nil }
        return "\(Int(ceil(duration * (1 - progress) / 60))) min left"
    }

    static func episodeIdentity(_ item: BaseItem) -> String? {
        guard item.type == "Episode" else { return nil }
        let season = item.parentIndexNumber.map { "S\($0)" } ?? ""
        let episode = item.indexNumber.map { "E\($0)" } ?? ""
        return [season + episode, item.name].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum HomeRecentFilter: String, CaseIterable, Identifiable {
    case all, movies, shows
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .shows: return "Shows"
        }
    }
}
