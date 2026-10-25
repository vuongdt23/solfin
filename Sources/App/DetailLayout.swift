import SwiftUI

/// Window points, rather than display pixels, govern all three detail pages.
/// Artwork and browsing collections span the window; hero copy stays grouped.
struct DetailLayout {
    let viewport: CGSize
    let railWidth: CGFloat

    var gutter: CGFloat { min(72, max(20, viewport.width * 0.025)) }
    var leadingInset: CGFloat { railWidth + gutter }
    var trailingInset: CGFloat { gutter }
    /// Collections use all available space, independently of the readable hero.
    var collectionWidth: CGFloat { max(0, viewport.width - leadingInset - trailingInset) }
    var contentWidth: CGFloat { min(1600, collectionWidth) }
    var usesColumns: Bool { contentWidth >= 1040 }
    var columnGap: CGFloat { min(56, max(24, contentWidth * 0.035)) }
    var copyWidth: CGFloat { usesColumns ? min(740, (contentWidth - columnGap) * 0.52) : min(760, contentWidth) }
    var secondaryWidth: CGFloat { usesColumns ? contentWidth - copyWidth - columnGap : copyWidth }
    var logoWidth: CGFloat { min(560, copyWidth) }
    var logoHeight: CGFloat { min(200, max(96, copyWidth * 0.29)) }
    var titleSize: CGFloat { min(68, max(32, copyWidth * 0.085)) }
    var topSpacing: CGFloat { min(160, max(24, viewport.height * 0.12)) }
    var sectionSpacing: CGFloat { contentWidth < 640 ? 28 : 40 }
    var artworkHeight: CGFloat { max(640, max(viewport.height, viewport.width * 9 / 16)) }
    var seriesHeroHeight: CGFloat { min(540, max(0, viewport.height * 0.48)) }
    // Grow cards gradually on large desktops as well as adding columns. A 4K
    // window gets eight generous cards, not a narrow five-column island or a
    // dense row of eleven small thumbnails. Tiled windows retain their sizing.
    var episodeMinimumWidth: CGFloat { min(440, 300 + max(0, collectionWidth - 1600) * 0.06) }
    var episodeColumns: Int { max(1, Int((collectionWidth + 20) / (episodeMinimumWidth + 20))) }
    var episodeCardWidth: CGFloat { max(0, (collectionWidth - CGFloat(episodeColumns - 1) * 20) / CGFloat(episodeColumns)) }
    var seasonCardWidth: CGFloat { min(240, 170 + max(0, collectionWidth - 1600) * 0.035) }
    var episodeStillSpace: CGFloat { max(0, collectionWidth - copyWidth - columnGap) }
    // Keep the still restrained in tiled windows, then let it scale gently as
    // the actual window grows. Width and height caps preserve space for the art.
    var episodeStillMaxWidth: CGFloat {
        min(1120, min(viewport.width * 0.44, 720 + max(0, viewport.width - 1440) * 0.22))
    }
    var episodeStillMaxHeight: CGFloat { min(760, max(440, viewport.height * 0.58)) }

    func episodeStillWidth(aspectRatio: CGFloat) -> CGFloat {
        min(episodeStillSpace, episodeStillMaxWidth, episodeStillMaxHeight * aspectRatio)
    }
}

/// Shared type scale for movie, series, and episode detail surfaces.
/// Values are in macOS points; reserve sub-14-point text for decorative glyphs only.
enum DetailTypography {
    static let micro: CGFloat = 14 // terse uppercase kicker labels only
    static let caption: CGFloat = 15
    static let supporting: CGFloat = 16
    static let metadata: CGFloat = 17
    static let body: CGFloat = 19
    static let cardTitle: CGFloat = 19
    static let sectionTitle: CGFloat = 24
    static let heroSubtitle: CGFloat = 30
    static let trackHeading: CGFloat = 15
    static let control: CGFloat = 17

    static func font(_ size: CGFloat, weight: Font.Weight = .regular,
                     design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}

/// Wrap metadata and actions as intact units instead of widening a tiled window.
struct DetailFlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, point) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  anchor: .topLeading, proposal: ProposedViewSize(width: result.widths[index], height: nil))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat?) -> (size: CGSize, positions: [CGPoint], widths: [CGFloat]) {
        let limit = max(0, width ?? .greatestFiniteMagnitude)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var positions: [CGPoint] = []
        var widths: [CGFloat] = []
        for subview in subviews {
            let itemWidth = min(limit, subview.sizeThatFits(.unspecified).width)
            let size = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if x > 0 && x + itemWidth > limit {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            widths.append(itemWidth)
            usedWidth = max(usedWidth, x + itemWidth)
            rowHeight = max(rowHeight, size.height)
            x += itemWidth + spacing
        }
        return (CGSize(width: width ?? usedWidth, height: y + rowHeight), positions, widths)
    }
}
