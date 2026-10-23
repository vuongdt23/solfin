import XCTest
@testable import PlaybackEngine

final class ArtworkFramingTests: XCTestCase {
    func testNoFacesUsesTopBiasedFill() {
        let framing = ArtworkFraming(imageSize: CGSize(width: 1920, height: 1080),
                                     canvasSize: CGSize(width: 2000, height: 540), faces: [])
        XCTAssertEqual(framing.imageFrame.width, 2000, accuracy: 0.01)
        XCTAssertEqual(framing.imageFrame.minY, (540 - 1125) * 0.18, accuracy: 0.01)
        XCTAssertFalse(framing.needsEdgeExtension)
    }

    func testHighFacesKeepHeadroomInUltrawideHero() {
        let faces = [CGRect(x: 0.5, y: 0.08, width: 0.08, height: 0.14),
                     CGRect(x: 0.82, y: 0.07, width: 0.07, height: 0.14)]
        let canvas = CGSize(width: 2000, height: 540)
        let framing = ArtworkFraming(imageSize: CGSize(width: 1920, height: 1080),
                                     canvasSize: canvas, faces: faces)
        for face in faces {
            let displayed = displayedRect(face, framing: framing)
            XCTAssertGreaterThanOrEqual(displayed.minY, canvas.height * 0.06)
            XCTAssertLessThanOrEqual(displayed.maxY, canvas.height * 0.78)
            XCTAssertGreaterThanOrEqual(displayed.minX, 0)
            XCTAssertLessThanOrEqual(displayed.maxX, canvas.width)
        }
        XCTAssertGreaterThan(framing.imageFrame.minY, -50)
    }

    func testHorizontalCropKeepsRightHandFaceVisible() {
        let face = CGRect(x: 0.85, y: 0.2, width: 0.1, height: 0.15)
        let framing = ArtworkFraming(imageSize: CGSize(width: 1920, height: 1080),
                                     canvasSize: CGSize(width: 900, height: 900), faces: [face])
        let displayed = displayedRect(face, framing: framing)
        XCTAssertGreaterThanOrEqual(displayed.minX, 0)
        XCTAssertLessThanOrEqual(displayed.maxX, 900)
    }

    func testSeparatedFacesRelaxScaleInsteadOfCuttingHeads() {
        let faces = [CGRect(x: 0.4, y: 0.05, width: 0.12, height: 0.2),
                     CGRect(x: 0.6, y: 0.72, width: 0.12, height: 0.2)]
        let framing = ArtworkFraming(imageSize: CGSize(width: 1920, height: 1080),
                                     canvasSize: CGSize(width: 2000, height: 500), faces: faces)
        XCTAssertTrue(framing.needsEdgeExtension)
        XCTAssertLessThan(framing.imageFrame.width, 2000)
        for face in faces {
            let displayed = displayedRect(face, framing: framing)
            XCTAssertGreaterThanOrEqual(displayed.minY, 0)
            XCTAssertLessThanOrEqual(displayed.maxY, 500)
        }
    }

    func testFacesNeverCauseAdditionalZoom() {
        let image = CGSize(width: 1920, height: 1080)
        let canvas = CGSize(width: 2000, height: 600)
        let framing = ArtworkFraming(imageSize: image, canvasSize: canvas,
                                     faces: [CGRect(x: 0.6, y: 0.4, width: 0.03, height: 0.05)])
        XCTAssertLessThanOrEqual(framing.imageFrame.width, 2000.001)
    }

    func testInvalidSizesReturnEmptyFrame() {
        let framing = ArtworkFraming(imageSize: .zero, canvasSize: CGSize(width: 100, height: 100), faces: [])
        XCTAssertEqual(framing.imageFrame, .zero)
        XCTAssertFalse(framing.needsEdgeExtension)
    }

    func testAnalysisRoundTripsIncludingNoFaces() throws {
        for faces in [[], [CGRect(x: 0.5, y: 0.1, width: 0.1, height: 0.2)]] {
            let encoded = try JSONEncoder().encode(ArtworkFaceAnalysis(faces: faces))
            let decoded = try JSONDecoder().decode(ArtworkFaceAnalysis.self, from: encoded)
            XCTAssertEqual(decoded.faces, faces)
        }
    }

    private func displayedRect(_ face: CGRect, framing: ArtworkFraming) -> CGRect {
        let image = framing.imageFrame
        return CGRect(x: image.minX + face.minX * image.width,
                      y: image.minY + face.minY * image.height,
                      width: face.width * image.width, height: face.height * image.height)
    }
}
