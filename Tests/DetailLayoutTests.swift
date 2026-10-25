import XCTest
import SwiftUI

final class DetailLayoutTests: XCTestCase {
    func testEpisodeStillSizingKeepsStillWithinResponsiveColumn() {
        let aspect: CGFloat = 16.0 / 9.0
        for viewport in [CGSize(width: 600, height: 480),
                         CGSize(width: 1280, height: 800),
                         CGSize(width: 1888, height: 1040),
                         CGSize(width: 3840, height: 2160)] {
            let layout = DetailLayout(viewport: viewport, railWidth: 64)
            let width = layout.episodeStillWidth(aspectRatio: aspect)
            XCTAssertGreaterThanOrEqual(width, 0)
            XCTAssertLessThanOrEqual(width, layout.episodeStillSpace)
            XCTAssertLessThanOrEqual(width, layout.episodeStillMaxWidth)
            XCTAssertLessThanOrEqual(width / aspect, layout.episodeStillMaxHeight)
        }
    }

    func testEpisodeStillUsesNaturalAspectRatioAndHeightCap() {
        let layout = DetailLayout(viewport: CGSize(width: 1888, height: 600), railWidth: 64)
        let wideWidth = layout.episodeStillWidth(aspectRatio: 2.0)
        let tallWidth = layout.episodeStillWidth(aspectRatio: 1.25)
        XCTAssertGreaterThanOrEqual(wideWidth, tallWidth)
        XCTAssertLessThanOrEqual(tallWidth / 1.25, layout.episodeStillMaxHeight)
        XCTAssertLessThanOrEqual(wideWidth / 2.0, layout.episodeStillMaxHeight)
    }

    func testEpisodeStillScalesUpGraduallyOnBiggerWindows() {
        let tiled = DetailLayout(viewport: CGSize(width: 1100, height: 800), railWidth: 64)
        let desktop = DetailLayout(viewport: CGSize(width: 1888, height: 1040), railWidth: 64)
        let fourK = DetailLayout(viewport: CGSize(width: 3840, height: 2160), railWidth: 64)
        let aspect: CGFloat = 16.0 / 9.0
        let tiledWidth = tiled.episodeStillWidth(aspectRatio: aspect)
        let desktopWidth = desktop.episodeStillWidth(aspectRatio: aspect)
        let fourKWidth = fourK.episodeStillWidth(aspectRatio: aspect)
        XCTAssertGreaterThan(desktopWidth, tiledWidth)
        XCTAssertGreaterThan(fourKWidth, desktopWidth)
        XCTAssertLessThanOrEqual(fourKWidth, fourK.episodeStillMaxWidth)
        XCTAssertLessThanOrEqual(fourKWidth / aspect, fourK.episodeStillMaxHeight)
    }

    func testEpisodeStillUsesWindowWidthBeyondBoundedCopyColumn() {
        let layout = DetailLayout(viewport: CGSize(width: 1888, height: 1040), railWidth: 64)
        let stillWidth = layout.episodeStillWidth(aspectRatio: 16.0 / 9.0)
        XCTAssertGreaterThan(layout.episodeStillSpace, layout.secondaryWidth)
        XCTAssertGreaterThan(stillWidth, 640)
        XCTAssertLessThanOrEqual(stillWidth, layout.episodeStillMaxWidth)
    }

    func testEpisodeStillRemainsWithinNarrowWindowSpace() {
        let layout = DetailLayout(viewport: CGSize(width: 1100, height: 800), railWidth: 64)
        XCTAssertFalse(layout.usesColumns)
        XCTAssertLessThanOrEqual(layout.episodeStillWidth(aspectRatio: 16.0 / 9.0), layout.episodeStillSpace)
    }

    func testDetailTypographyHasReadableConsistentHierarchy() {
        XCTAssertGreaterThanOrEqual(DetailTypography.micro, 14)
        XCTAssertGreaterThanOrEqual(DetailTypography.caption, 15)
        XCTAssertGreaterThanOrEqual(DetailTypography.supporting, 16)
        XCTAssertGreaterThanOrEqual(DetailTypography.metadata, 17)
        XCTAssertGreaterThan(DetailTypography.body, DetailTypography.metadata)
        XCTAssertGreaterThan(DetailTypography.cardTitle, DetailTypography.supporting)
        XCTAssertGreaterThan(DetailTypography.sectionTitle, DetailTypography.cardTitle)
        XCTAssertGreaterThanOrEqual(DetailTypography.control, DetailTypography.metadata)
    }

    func testContentAndColumnsStayInsideWindowWhenResizing() {
        for rail: CGFloat in [64, 210] {
            for width in stride(from: 600, through: 5120, by: 13) {
                let layout = DetailLayout(viewport: CGSize(width: width, height: 800), railWidth: rail)
                XCTAssertGreaterThan(layout.contentWidth, 0)
                XCTAssertLessThanOrEqual(layout.leadingInset + layout.contentWidth + layout.trailingInset,
                                         CGFloat(width) + 0.001)
                XCTAssertLessThanOrEqual(layout.logoWidth, layout.copyWidth)
                XCTAssertLessThanOrEqual(layout.copyWidth, layout.contentWidth)
                if layout.usesColumns {
                    XCTAssertEqual(layout.copyWidth + layout.columnGap + layout.secondaryWidth,
                                   layout.contentWidth, accuracy: 0.001)
                    XCTAssertGreaterThanOrEqual(layout.secondaryWidth, 460)
                }
            }
        }
    }

    func testNarrowWindowsStackAndExpandedRailCanTriggerStacking() {
        for width: CGFloat in [600, 680, 800, 900, 1024] {
            XCTAssertFalse(DetailLayout(viewport: CGSize(width: width, height: 800), railWidth: 64).usesColumns)
        }
        XCTAssertTrue(DetailLayout(viewport: CGSize(width: 1200, height: 800), railWidth: 64).usesColumns)
        XCTAssertFalse(DetailLayout(viewport: CGSize(width: 1200, height: 800), railWidth: 210).usesColumns)
    }

    func testUltrawideContentIsBoundedButArtworkOverflows() {
        let layout = DetailLayout(viewport: CGSize(width: 3440, height: 1440), railWidth: 64)
        XCTAssertEqual(layout.contentWidth, 1600)
        XCTAssertLessThan(layout.leadingInset, 150)
        XCTAssertGreaterThan(layout.artworkHeight, layout.viewport.height)
        XCTAssertEqual(layout.copyWidth, 740)
        XCTAssertGreaterThan(layout.collectionWidth, layout.contentWidth)
        XCTAssertGreaterThan(layout.episodeColumns, 5)
    }

    func testHeightChangesSpacingNotColumnChoice() {
        let short = DetailLayout(viewport: CGSize(width: 1440, height: 480), railWidth: 64)
        let tall = DetailLayout(viewport: CGSize(width: 1440, height: 1600), railWidth: 64)
        XCTAssertEqual(short.usesColumns, tall.usesColumns)
        XCTAssertEqual(short.copyWidth, tall.copyWidth)
        XCTAssertLessThan(short.topSpacing, tall.topSpacing)
        XCTAssertLessThan(short.seriesHeroHeight, tall.seriesHeroHeight)
        XCTAssertLessThanOrEqual(tall.topSpacing, 160)
        XCTAssertLessThanOrEqual(tall.seriesHeroHeight, 540)
    }

    func testEpisodeGridFillsAvailableWidthWithoutTinyCards() {
        for rail: CGFloat in [64, 210] {
            for width in stride(from: 600, through: 4000, by: 17) {
                let layout = DetailLayout(viewport: CGSize(width: width, height: 900), railWidth: rail)
                XCTAssertGreaterThanOrEqual(layout.episodeColumns, 1)
                XCTAssertGreaterThanOrEqual(layout.episodeCardWidth, layout.episodeMinimumWidth)
                XCTAssertEqual(CGFloat(layout.episodeColumns) * layout.episodeCardWidth
                               + CGFloat(layout.episodeColumns - 1) * 20,
                               layout.collectionWidth, accuracy: 0.001)
                XCTAssertEqual(layout.leadingInset + layout.collectionWidth + layout.trailingInset,
                               CGFloat(width), accuracy: 0.001)
            }
        }
    }

    func testFourKCollectionFillsWindowWithLargerCardsAndReadableCopy() {
        // Regression for the supplied 3776-point-wide screenshot: the old grid
        // stopped at 1600 points, leaving more than half the content area empty.
        let layout = DetailLayout(viewport: CGSize(width: 3776, height: 2079), railWidth: 64)
        XCTAssertEqual(layout.collectionWidth, 3568)
        XCTAssertEqual(layout.episodeColumns, 8)
        XCTAssertEqual(layout.episodeCardWidth, 428.5)
        XCTAssertEqual(layout.copyWidth, 740)
        XCTAssertEqual(layout.contentWidth, 1600)
        XCTAssertGreaterThan(layout.seasonCardWidth, 230)
        XCTAssertLessThanOrEqual(layout.seasonCardWidth, 240)
        let rowsForTwentyEpisodes = Int(ceil(20.0 / Double(layout.episodeColumns)))
        XCTAssertEqual(rowsForTwentyEpisodes, 3)
    }

    func testTiledAndRetinaScaledWindowsKeepCompactCardSizing() {
        for width: CGFloat in [600, 900, 1280, 1440, 1600] {
            let layout = DetailLayout(viewport: CGSize(width: width, height: 900), railWidth: 64)
            XCTAssertEqual(layout.collectionWidth, layout.contentWidth)
            XCTAssertEqual(layout.episodeMinimumWidth, 300)
            XCTAssertEqual(layout.seasonCardWidth, 170)
        }
    }

    @MainActor func testMetadataFlowWrapsWithoutIncreasingWidth() throws {
        let renderer = ImageRenderer(content: DetailFlowLayout(spacing: 12, rowSpacing: 10) {
            Color.white.frame(width: 100, height: 20)
            Color.white.frame(width: 100, height: 20)
            Color.white.frame(width: 100, height: 20)
        }.frame(width: 220))
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 220)
        XCTAssertEqual(image.size.height, 50)
    }

    @MainActor func testMetadataFlowStaysInOneRowWhenItFits() throws {
        let renderer = ImageRenderer(content: DetailFlowLayout(spacing: 12, rowSpacing: 10) {
            Color.white.frame(width: 100, height: 20)
            Color.white.frame(width: 100, height: 20)
            Color.white.frame(width: 100, height: 20)
        }.frame(width: 324))
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 324)
        XCTAssertEqual(image.size.height, 20)
    }

    @MainActor func testMetadataFlowAccountsForDifferentRowHeights() throws {
        let renderer = ImageRenderer(content: DetailFlowLayout(spacing: 12, rowSpacing: 10) {
            Color.white.frame(width: 100, height: 30)
            Color.white.frame(width: 100, height: 20)
            Color.white.frame(width: 100, height: 40)
        }.frame(width: 220))
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 220)
        XCTAssertEqual(image.size.height, 80)
    }

    func testZeroSizedTransientViewportHasNonnegativeGeometry() {
        let layout = DetailLayout(viewport: .zero, railWidth: 64)
        XCTAssertEqual(layout.contentWidth, 0)
        XCTAssertEqual(layout.copyWidth, 0)
        XCTAssertEqual(layout.logoWidth, 0)
        XCTAssertEqual(layout.episodeColumns, 1)
        XCTAssertEqual(layout.episodeCardWidth, 0)
    }
}
