import Foundation

/// A complete, edge-to-edge editorial block. Choose whole rows, not a fixed
/// number of titles; the caller puts everything else in the overflow shelf.
struct HomeRecentGeometry {
    enum Artwork {
        case poster, thumbnail

        var aspectRatio: CGFloat { self == .poster ? 2 / 3 : 16 / 9 }
        var minimumWidth: CGFloat { self == .poster ? 150 : 220 }
        var maximumWidth: CGFloat { self == .poster ? 360 : 460 }
    }

    static let sectionSpacing: CGFloat = 18
    static let cardSpacing: CGFloat = 14
    // Two compact text lines (16 + 12), plus two 10-point gaps.
    static let captionHeight: CGFloat = 48

    let sideBySide: Bool
    let artwork: Artwork
    let columns: Int
    let rows: Int
    let leadWidth: CGFloat
    let leadHeight: CGFloat
    let supportingWidth: CGFloat
    let cardWidth: CGFloat
    let artworkHeight: CGFloat

    var supportingCount: Int { columns * rows }
    var displayedCount: Int { 1 + supportingCount }
    var supportingHeight: CGFloat {
        CGFloat(rows) * (artworkHeight + Self.captionHeight)
            + CGFloat(max(0, rows - 1)) * Self.cardSpacing
    }

    static func resolve(width: CGFloat, itemCount: Int) -> Self {
        let width = max(1, width)
        let count = max(0, itemCount - 1)
        let spacing = cardSpacing
        guard count > 0 else {
            return Self(sideBySide: false, artwork: .thumbnail, columns: 0, rows: 0,
                        leadWidth: width, leadHeight: min(560, max(320, width * 0.46)),
                        supportingWidth: 0, cardWidth: 0, artworkHeight: 0)
        }

        guard width >= 1_000 else {
            // Narrow windows keep the newest title above a full thumbnail row.
            let columns = min(count, max(1, Int((width + spacing) / 254)))
            let cardWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            return Self(sideBySide: false, artwork: .thumbnail, columns: columns, rows: 1,
                        leadWidth: width, leadHeight: min(460, max(320, width * 0.46)),
                        supportingWidth: width, cardWidth: cardWidth,
                        artworkHeight: cardWidth / Artwork.thumbnail.aspectRatio)
        }

        let preferredLeadWidth = width * 0.42
        let targetHeight = min(600, max(360, preferredLeadWidth * 0.62))
        var best: (layout: Self, score: CGFloat)?
        for artwork in [Artwork.poster, .thumbnail] {
            for rows in (artwork == .poster ? [1] : [1, 2]) {
                guard count >= rows else { continue }
                for columns in 1...min(12, count / rows) {
                    let gaps = CGFloat(columns - 1) * spacing
                    // With few items the highlight absorbs the extra width,
                    // instead of leaving empty columns or stretching a poster.
                    let supportingWidth = min(width - preferredLeadWidth - sectionSpacing,
                                              CGFloat(columns) * artwork.maximumWidth + gaps)
                    let cardWidth = (supportingWidth - gaps) / CGFloat(columns)
                    guard cardWidth > 0 else { continue }
                    let naturalHeight = CGFloat(rows) * (cardWidth / artwork.aspectRatio + captionHeight)
                        + CGFloat(rows - 1) * spacing
                    let height = max(320, naturalHeight)
                    let score = abs(height - targetHeight)
                        + max(0, artwork.minimumWidth - cardWidth) * 4
                        + max(0, height - 680) * 4
                        + (artwork == .thumbnail ? 24 : 0)
                        + (width - preferredLeadWidth - sectionSpacing - supportingWidth) * 0.3
                    let layout = Self(sideBySide: true, artwork: artwork, columns: columns, rows: rows,
                                      leadWidth: width - supportingWidth - sectionSpacing,
                                      leadHeight: height, supportingWidth: supportingWidth,
                                      cardWidth: cardWidth,
                                      artworkHeight: (height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
                                        - captionHeight)
                    if best == nil || score < best!.score { best = (layout, score) }
                }
            }
        }
        // At least one single-column candidate exists for every nonempty input.
        return best!.layout
    }
}
