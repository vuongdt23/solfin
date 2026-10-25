import SwiftUI
import JellyfinKit
import PlaybackEngine

/// A library tile blends its identity with a playful, independently navigable artwork collage.
struct HomeLibraryTile: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: BaseItem
    let posters: [BaseItem]
    var width: CGFloat = 480
    var tileHeight: CGFloat? = nil
    var gallery = false
    var artworkStyle: HomeLibraryArtworkStyle = .fan
    @State private var hovering = false
    @State private var hoveredPosterIndex: Int?
    @State private var isPosterPointerInside = false
    @State private var openPosterIndex: Int?
    @State private var posterOpenTask: Task<Void, Never>?

    private var height: CGFloat { tileHeight ?? width * 0.52 }
    private var posterWidth: CGFloat { height * 0.49 }
    private var posterHeight: CGFloat { posterWidth * 1.5 }
    private var fanCardCount: Int {
        min(max(5, Int(width / 110)), max(1, posters.count))
    }
    private var collageCardCount: Int { min(14, posters.count) }
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
        NavigationLink(value: openPosterIndex.flatMap(poster(at:)) ?? item) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.065, green: 0.062, blue: 0.08))
                    .overlay {
                        LinearGradient(colors: [.clear, accent.opacity(0.07)],
                                       startPoint: .leading, endPoint: .trailing)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.12))
                    }

                if openPosterIndex != nil {
                    Label("Ready to open", systemImage: "arrow.up.right.square.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.82), in: Capsule())
                        .overlay { Capsule().strokeBorder(.white.opacity(0.4)) }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .zIndex(100)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(14)
                        .allowsHitTesting(false)
                }

                Group {
                    if gallery && hoveredPosterIndex == nil {
                        artworkComposition
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    } else if gallery {
                        artworkComposition
                    } else {
                        posterStack
                    }
                }
                .accessibilityHidden(true)

                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(item.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(.black.opacity(0.72), in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: gallery ? .bottomLeading : .leading)
                .padding(.leading, gallery ? 18 : width * 0.07)
                .padding(.bottom, gallery ? 18 : 0)
                .zIndex(200)
                .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if !inside && hoveredPosterIndex == nil {
                posterOpenTask?.cancel()
                posterOpenTask = nil
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { openPosterIndex = nil }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(openPosterIndex.flatMap(poster(at:)).map { "Open \($0.name)" } ?? "Browse \(item.name)")
        .help(openPosterIndex.flatMap(poster(at:)).map { "Open \($0.name)" } ?? "Open \(item.name)")
        .onDisappear { posterOpenTask?.cancel() }
        // Lift the whole tile above neighboring grid/shelf cells while an artwork
        // card breaks out, not just the transformed image inside this tile.
        .zIndex(hoveredPosterIndex == nil ? 0 : 50)
    }

    @ViewBuilder
    private var artworkComposition: some View {
        switch artworkStyle {
        case .fan: posterFan
        case .random: randomMosaic
        }
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
    }

    /// Seeded poster and thumbnail cards overlap in varied sizes and orientations,
    /// giving each library a distinct collage while keeping the layout reproducible.
    private var randomMosaic: some View {
        let cells = makeMosaicLayout(count: collageCardCount)
        return ZStack {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                collageCard(cell)
                    .rotationEffect(.degrees(cell.rotation))
                    .zIndex(hoveredPosterIndex == cell.index ? 30 : Double(cell.index) / 100)
                    .position(x: width * cell.centerX, y: height * cell.centerY)
            }
        }
        .frame(width: width, height: height)
    }

    private struct MosaicCell {
        let index: Int
        let centerX: CGFloat
        let centerY: CGFloat
        let width: CGFloat
        let height: CGFloat
        let landscape: Bool
        let rotation: Double
    }

    private struct MosaicRandom {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
        mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    }

    private func makeMosaicLayout(count: Int) -> [MosaicCell] {
        guard count > 0 else { return [] }
        let seedText = item.id + posters.prefix(count).map(\.id).joined(separator: "|")
        var seed: UInt64 = 14_695_981_039_346_656_037
        for byte in seedText.utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        var random = MosaicRandom(state: seed == 0 ? 1 : seed)

        let tileAspect = width / height
        let cardSizes: [(landscape: Bool, width: CGFloat, height: CGFloat, rotation: Double)] = (0..<count).map { index in
            let landscape = random.next().isMultiple(of: 2)
            let aspect: CGFloat = landscape ? 16.0 / 9.0 : 2.0 / 3.0
            let sizeWave = CGFloat((sin(Double(index) * 2.17 + random.unit() * 0.8) + 1) / 2)
            let readableMinimum = landscape
                ? max(0.31, min(0.40, 250 / width))
                : max(0.25, min(0.32, 190 / width))
            let variedRange: CGFloat = landscape ? 0.12 : 0.10
            let widthFraction = (readableMinimum + variedRange * sizeWave) * 0.75
            return (landscape, widthFraction, widthFraction * tileAspect / aspect,
                    Double(random.unit() - 0.5) * 7)
        }

        // Keep every card's full bounds—including its largest hover scale and
        // shadow clearance—inside a second, invisible box inset from the tile.
        let maximumHoverScale: CGFloat = 1.2
        let edgeClearanceX = 22 / width
        // Let cards break out up to 8pt above and below the library tile while
        // keeping the horizontal safety boundary against neighboring components.
        let edgeClearanceY = -min(8, height * 0.035) / height
        let boundedCardSizes = cardSizes.map { size in
            let halfWidth = rotatedHalfExtent(width: size.width, height: size.height,
                                              degrees: size.rotation, horizontal: true)
            let halfHeight = rotatedHalfExtent(width: size.width, height: size.height,
                                               degrees: size.rotation, horizontal: false)
            let allowedHalfWidth = max(0, 0.5 - edgeClearanceX)
            let allowedHalfHeight = 0.5 - edgeClearanceY
            let fitScale = min(1,
                               allowedHalfWidth / (halfWidth * maximumHoverScale),
                               allowedHalfHeight / (halfHeight * maximumHoverScale))
            return (landscape: size.landscape, width: size.width * fitScale,
                    height: size.height * fitScale, rotation: size.rotation)
        }
        for sizeScale in [1.0, 0.94, 0.88] {
            let sizes = boundedCardSizes.map { size in
                (landscape: size.landscape, width: size.width * sizeScale,
                 height: size.height * sizeScale, rotation: size.rotation)
            }
            var best: [MosaicCell] = []
            var bestCoverage = -1
            for _ in 0..<16 {
                var cells: [MosaicCell] = []
                var valid = true
                for (index, size) in sizes.enumerated() {
                    let halfWidth = rotatedHalfExtent(width: size.width * maximumHoverScale,
                                                      height: size.height * maximumHoverScale,
                                                      degrees: size.rotation, horizontal: true)
                    let halfHeight = rotatedHalfExtent(width: size.width * maximumHoverScale,
                                                       height: size.height * maximumHoverScale,
                                                       degrees: size.rotation, horizontal: false)
                    var placed: MosaicCell?
                    let minX = edgeClearanceX + halfWidth
                    let maxX = 1 - edgeClearanceX - halfWidth
                    let minY = edgeClearanceY + halfHeight
                    let maxY = 1 - edgeClearanceY - halfHeight
                    guard minX <= maxX, minY <= maxY else { valid = false; break }
                    for _ in 0..<36 {
                        let x = minX + random.unit() * (maxX - minX)
                        let y = minY + random.unit() * (maxY - minY)
                        let candidate = MosaicCell(index: index, centerX: x, centerY: y,
                                                   width: size.width, height: size.height,
                                                   landscape: size.landscape, rotation: size.rotation)
                        let centersClear = cells.allSatisfy { existing in
                            !point(x: x, y: y, isInside: existing)
                                && !point(x: existing.centerX, y: existing.centerY, isInside: candidate)
                        }
                        guard centersClear else { continue }
                        placed = candidate
                        break
                    }
                    guard let placed else { valid = false; break }
                    cells.append(placed)
                }
                guard valid else { continue }
                let coverage = mosaicCoverage(cells)
                if coverage > bestCoverage {
                    best = cells
                    bestCoverage = coverage
                }
            }
            if best.count == count { return best }
        }

        // Fallback spiral uses the same edge-safe box, also accounting for the
        // largest hover scale so cards cannot break out of the tile.
        return boundedCardSizes.enumerated().map { index, size in
            let cardWidth = size.width * 0.88
            let cardHeight = size.height * 0.88
            let halfWidth = rotatedHalfExtent(width: cardWidth * maximumHoverScale,
                                              height: cardHeight * maximumHoverScale,
                                              degrees: size.rotation, horizontal: true)
            let halfHeight = rotatedHalfExtent(width: cardWidth * maximumHoverScale,
                                               height: cardHeight * maximumHoverScale,
                                               degrees: size.rotation, horizontal: false)
            let minX = edgeClearanceX + halfWidth
            let maxX = 1 - edgeClearanceX - halfWidth
            let minY = edgeClearanceY + halfHeight
            let maxY = 1 - edgeClearanceY - halfHeight
            let angle = Double(index) * 2.399963
            let radius = 0.43 * sqrt(CGFloat(index) / CGFloat(max(1, count - 1)))
            let proposedX = 0.5 + cos(angle) * radius
            let proposedY = 0.5 + sin(angle) * radius * 0.8
            return MosaicCell(index: index,
                              centerX: min(max(proposedX, minX), maxX),
                              centerY: min(max(proposedY, minY), maxY),
                              width: cardWidth, height: cardHeight,
                              landscape: size.landscape, rotation: size.rotation)
        }
    }

    private func rotatedHalfExtent(width: CGFloat, height: CGFloat, degrees: Double,
                                   horizontal: Bool) -> CGFloat {
        let radians = abs(degrees) * .pi / 180
        let alongWidth = width * CGFloat(cos(radians))
        let alongHeight = height * CGFloat(sin(radians))
        return (horizontal ? alongWidth + alongHeight : width * CGFloat(sin(radians))
                + height * CGFloat(cos(radians))) / 2
    }

    private func point(x: CGFloat, y: CGFloat, isInside cell: MosaicCell) -> Bool {
        let halfWidth = rotatedHalfExtent(width: cell.width, height: cell.height,
                                          degrees: cell.rotation, horizontal: true)
        let halfHeight = rotatedHalfExtent(width: cell.width, height: cell.height,
                                           degrees: cell.rotation, horizontal: false)
        return abs(x - cell.centerX) < halfWidth && abs(y - cell.centerY) < halfHeight
    }

    private func mosaicCoverage(_ cells: [MosaicCell]) -> Int {
        let columns = 16
        let rows = 10
        var covered = 0
        for row in 0..<rows {
            for column in 0..<columns {
                let x = (CGFloat(column) + 0.5) / CGFloat(columns)
                let y = (CGFloat(row) + 0.5) / CGFloat(rows)
                if cells.contains(where: { point(x: x, y: y, isInside: $0) }) { covered += 1 }
            }
        }
        return covered
    }

    @ViewBuilder
    private func collageCard(_ cell: MosaicCell) -> some View {
        let isHovered = hoveredPosterIndex == cell.index
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        LibraryTilePoster(url: collageArtworkURL(at: cell.index, landscape: cell.landscape),
                          icon: icon, accent: accent)
            .frame(width: width * cell.width, height: height * cell.height)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(openPosterIndex == cell.index ? .white.opacity(0.78) : .white.opacity(0.14),
                                   lineWidth: openPosterIndex == cell.index ? 2 : 1)
            }
            .shadow(color: .black.opacity(0.55), radius: openPosterIndex == cell.index ? 22 : 12,
                    x: 0, y: openPosterIndex == cell.index ? 12 : 6)
            .cardHoverEffect(isActive: isHovered, lift: 0, scale: openPosterIndex == cell.index ? 1.2 : 1.12)
            .contentShape(shape)
            .onHover { updatePosterHover(cell.index, inside: $0) }
    }

    private func collageArtworkURL(at index: Int, landscape: Bool) -> URL? {
        guard posters.indices.contains(index) else { return nil }
        let poster = posters[index]
        if landscape {
            return appState.api.thumbnailImageURL(for: poster, maxWidth: 900)
                ?? appState.api.backdropImageURL(for: poster, maxWidth: 900)
                ?? appState.api.primaryImageURL(for: poster, maxHeight: 640)
        }
        return appState.api.primaryImageURL(for: poster, maxHeight: 900)
            ?? appState.api.thumbnailImageURL(for: poster, maxWidth: 900)
    }

    private func updatePosterHover(_ index: Int, inside: Bool) {
        if inside {
            isPosterPointerInside = true
            hoveredPosterIndex = index
            posterOpenTask?.cancel()
            openPosterIndex = nil
            posterOpenTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled, isPosterPointerInside, hoveredPosterIndex == index else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                    openPosterIndex = index
                }
            }
        } else if hoveredPosterIndex == index {
            isPosterPointerInside = false
            hoveredPosterIndex = nil
            openPosterIndex = nil
            posterOpenTask?.cancel()
            posterOpenTask = nil
        }
    }

    private func poster(at index: Int) -> BaseItem? {
        posters.indices.contains(index) ? posters[index] : nil
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
            .overlay {
                shape.strokeBorder(openPosterIndex == index ? .white.opacity(0.78) : .white.opacity(0.14),
                                   lineWidth: openPosterIndex == index ? 2 : 1)
            }
            .cardHoverEffect(isActive: isHovered, lift: 16, scale: openPosterIndex == index ? 1.2 : 1.12)
            .contentShape(shape)
            .onHover { updatePosterHover(index, inside: $0) }
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
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
