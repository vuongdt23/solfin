import Foundation

/// Layout and hero size are separate so switching modes preserves the user's
/// preferred Cinematic presentation. Raw values are stable persisted identifiers.
enum HomeLayout: String, CaseIterable, Identifiable {
    case cinematic
    case watchNow
    case library

    var id: String { rawValue }
    static func saved(_ rawValue: String) -> Self { Self(rawValue: rawValue) ?? .cinematic }

    var title: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .watchNow: return "Watch Now"
        case .library: return "Library"
        }
    }
    var symbol: String {
        switch self {
        case .cinematic: return "sparkles.tv"
        case .watchNow: return "play.circle"
        case .library: return "square.grid.2x2"
        }
    }
    var summary: String {
        switch self {
        case .cinematic: return "Discover something to watch with featured artwork and media shelves."
        case .watchNow: return "Pick up where you left off, with Continue Watching and Next Up first."
        case .library: return "Browse your libraries and recent additions without a large hero."
        }
    }

    var sections: [HomeSection] {
        switch self {
        case .cinematic: return [.watching, .discover, .recentlyAdded, .libraries]
        case .watchNow: return [.watching, .discover, .recentlyAdded, .libraries]
        case .library: return [.libraries, .recentlyAdded, .watching]
        }
    }
}

enum HomeLibraryArtworkStyle: String, CaseIterable, Identifiable {
    case fan, random

    var id: String { rawValue }
    static func saved(_ rawValue: String) -> Self { Self(rawValue: rawValue) ?? .fan }
    var title: String {
        switch self {
        case .fan: return "Poster Fan"
        case .random: return "Random Collage"
        }
    }
}

enum HomeSection: String, Identifiable {
    case watching, libraries, recentlyAdded, discover
    var id: String { rawValue }
}

enum HomeHeroStyle: String, CaseIterable, Identifiable {
    case full
    case spotlight

    var id: String { rawValue }
    static func saved(_ rawValue: String) -> Self { Self(rawValue: rawValue) ?? .full }
    var title: String { self == .full ? "Full-size carousel" : "Compact Spotlight" }
}
