import SwiftUI
import JellyfinKit
import PlaybackEngine

/// A library's identity stays separate from its artwork: randomized posters form a
/// small collection on the right, never a second baked-in library title.
struct HomeLibraryTile: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: BaseItem
    let posters: [BaseItem]
    var width: CGFloat = 480
    var tileHeight: CGFloat? = nil
    var gallery = false
    var artworkStyle: HomeLibraryArtworkStyle = .wall
    @State private var hovering = false
    @State private var hoveredPosterIndex: Int?

    private var height: CGFloat { tileHeight ?? width * 0.52 }
    private var posterWidth: CGFloat { height * 0.49 }
    private var posterHeight: CGFloat { posterWidth * 1.5 }
    private var fanCardCount: Int {
        min(max(5, Int(width / 110)), max(1, posters.count))
    }
    private var cornerRadius: CGFloat { 22 }

    private var icon: String {
        switch item.collectionType?.lowercased() {
        case "movies": return "film"
        case "tvshows": return "tv"
        default: return "rectangle.stack"
        }
    }

    private var accent: Color {
        item.collectionType?.lowercased() == "tvshows"
            ? Color(red: 0.72, green: 0.56, blue: 0.96) : SolfinDesign.solarGold
    }

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.065, green: 0.062, blue: 0.08))
                LinearGradient(colors: [.clear, accent.opacity(hovering ? 0.14 : 0.07)],
                               startPoint: .leading, endPoint: .trailing)
                    .allowsHitTesting(false)
                Group {
                    if gallery { artworkComposition } else { posterStack }
                }
                .offset(y: hovering && !reduceMotion ? -3 : 0)
                .accessibilityHidden(true)
                if gallery || artworkStyle == .random {
                    LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.88)],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(accent)
                    Text(item.name)
                        .font(.system(size: gallery && width >= 550 ? 44 : width >= 460 ? 34 : 30, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        Text("Explore library")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(hovering ? 0.86 : 0.6))
                }
                .frame(width: width * (gallery ? 0.8 : 0.4), alignment: .leading)
                .padding(.leading, width * 0.07)
                .frame(maxHeight: .infinity, alignment: gallery ? .bottomLeading : .leading)
                .padding(.bottom, gallery ? 26 : 0)
                .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Browse \(item.name)")
        .help("Open \(item.name)")
    }

    @ViewBuilder
    private var artworkComposition: some View {
        switch artworkStyle {
        case .wall: tiltedWall
        case .fan: posterFan
        case .grid: cleanGrid
        case .random: randomMosaic
        }
    }

    /// Full-bleed poster arrangements: the collage spans the entire card, with
    /// the library identity layered over it rather than reserving an empty text column.
    private var tiltedWall: some View {
        ZStack {
            ForEach((0..<6).reversed(), id: \.self) { index in
                let x = 0.10 + CGFloat(index) * 0.16
                positionedPoster(index, width: 0.205, height: 0.94,
                                 x: x, y: index.isMultiple(of: 2) ? 0.49 : 0.53,
                                 rotation: Double(index % 3 - 1) * 2.5)
                    .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 4)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var posterFan: some View {
        ZStack {
            ForEach(0..<fanCardCount, id: \.self) { index in
                let midpoint = CGFloat(fanCardCount - 1) / 2
                let spread = midpoint == 0 ? 0 : (CGFloat(index) - midpoint) / midpoint
                let cardHeight = height * 0.92
                // Larger portrait cards are laid out across a broad arc. A modest
                // rotation and a responsive count keep the artwork readable instead
                // of compressing everything into a tight central pile.
                let cardWidth = cardHeight * 0.68
                let angle = Double(spread) * 18
                let x = width * (0.12 + CGFloat(index) / CGFloat(max(1, fanCardCount - 1)) * 0.76)
                let baseline = height * (0.94 - abs(spread) * 0.055)
                posterCell(index, width: cardWidth, height: cardHeight, cornerRadius: 10)
                    .rotationEffect(.degrees(angle), anchor: .bottom)
                    .position(x: x, y: baseline - cardHeight / 2)
                    .shadow(color: .black.opacity(0.48), radius: 11, x: 0, y: 7)
                    .zIndex(hoveredPosterIndex == index ? 30 : Double(index))
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private var cleanGrid: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let column = index % 4
                let row = index / 4
                positionedPoster(index, width: 0.255, height: 0.54,
                                 x: 0.125 + CGFloat(column) * 0.25,
                                 y: row == 0 ? 0.23 : 0.77)
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    /// A seeded, variable-width two-row mosaic. Row widths are normalized to
    /// exactly fill the card, while different card counts and proportions make
    /// each library's collage feel distinct without leaving unused pockets.
    private var randomMosaic: some View {
        let cells = makeMosaicLayout(count: min(posters.count, 24))
        return ZStack {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                posterCell(cell.index,
                           width: max(1, width * cell.width - 7),
                           height: max(1, height * cell.height - 7))
                    .rotationEffect(.degrees(cell.rotation))
                    .zIndex(hoveredPosterIndex == cell.index ? 30 : 0)
                    .position(x: width * (cell.x + cell.width / 2),
                              y: height * (cell.y + cell.height / 2))
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private struct MosaicCell {
        let index: Int
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let rotation: Double
    }

    private struct MosaicRandom {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
        mutating func unit() -> CGFloat {
            CGFloat(next() >> 11) / CGFloat(1 << 53)
        }
    }

    private func makeMosaicLayout(count: Int) -> [MosaicCell] {
        guard count > 0 else { return [] }
        let seedText = item.id + posters.prefix(count).map(\.id).joined(separator: "|")
        var seed: UInt64 = 14_695_981_039_346_656_037
        for byte in seedText.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        var random = MosaicRandom(state: seed == 0 ? 1 : seed)

        let rowCount = count < 3 ? count : 2 + Int(random.next() % 2)
        var rowCounts = Array(repeating: 1, count: rowCount)
        for _ in rowCount..<count {
            rowCounts[Int(random.next() % UInt64(rowCount))] += 1
        }
        let heightWeights = (0..<rowCount).map { _ in 0.78 + random.unit() * 0.44 }
        let totalHeightWeight = heightWeights.reduce(0, +)
        let rowHeights = heightWeights.map { $0 / totalHeightWeight }

        var cells: [MosaicCell] = []
        var index = 0
        var y: CGFloat = 0
        for row in rowCounts.indices {
            let rowHeight = rowHeights[row]
            let weights = (0..<rowCounts[row]).map { _ in 0.78 + random.unit() * 0.44 }
            let weightTotal = weights.reduce(0, +)
            var x: CGFloat = 0
            for weight in weights {
                let cellWidth = weight / weightTotal
                let rotation = Double(random.unit() - 0.5) * 2.4
                cells.append(MosaicCell(index: index, x: x, y: y,
                                        width: cellWidth, height: rowHeight, rotation: rotation))
                x += cellWidth
                index += 1
            }
            y += rowHeight
        }
        return cells
    }

    private func positionedPoster(_ index: Int, width widthFraction: CGFloat, height heightFraction: CGFloat,
                                  x: CGFloat, y: CGFloat, rotation: Double = 0) -> some View {
        posterCell(index, width: width * widthFraction, height: height * heightFraction)
            .rotationEffect(.degrees(rotation))
            .zIndex(hoveredPosterIndex == index ? 30 : 0)
            .position(x: width * x, y: height * y)
    }

    private func posterCell(_ index: Int, width: CGFloat, height: CGFloat,
                            cornerRadius: CGFloat = 8) -> some View {
        let isHovered = hoveredPosterIndex == index
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return LibraryTilePoster(url: posters.indices.contains(index)
                                 ? appState.api.primaryImageURL(for: posters[index], maxHeight: 640)
                                 : nil,
                                 icon: icon, accent: accent)
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.white.opacity(0.16)) }
            .scaleEffect(isHovered && !reduceMotion ? 1.035 : 1)
            .offset(y: isHovered && !reduceMotion ? -5 : 0)
            .contentShape(shape)
            .onHover { inside in
                if inside { hoveredPosterIndex = index }
                else if hoveredPosterIndex == index { hoveredPosterIndex = nil }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.76),
                       value: isHovered)
    }

    private var posterStack: some View {
        ZStack {
            // Draw back to front, with the first random title in the foreground.
            ForEach((0..<3).reversed(), id: \.self) { index in
                posterCell(index, width: posterWidth, height: posterHeight, cornerRadius: 10)
                    .shadow(color: .black.opacity(0.5), radius: 12, x: -6, y: 8)
                    .rotationEffect(.degrees(Double(index - 1) * (hovering && !reduceMotion ? 13 : 10)))
                    .position(x: width * (0.655 + CGFloat(index) * 0.085),
                              y: height * (index == 1 ? 0.5 : 0.54))
            }
        }
        .frame(width: width, height: height)
    }
}

/// Quiet placeholders rather than three spinners while cached images load.
private struct LibraryTilePoster: View {
    let url: URL?
    let icon: String
    let accent: Color
    @State private var image: NSImage?

    var body: some View {
        LinearGradient(colors: [accent.opacity(0.24), Color(red: 0.1, green: 0.08, blue: 0.15)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(accent.opacity(0.5))
                }
            }
            .clipped()
            .task(id: url) {
                image = nil
                guard let url else { return }
                let loaded = await MediaAssetCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}
