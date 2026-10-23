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

    func testLowerHeadsDoNotShrinkOrMoveHighestHeadFraming() {
        let highest = CGRect(x: 0.4, y: 0.05, width: 0.12, height: 0.2)
        let lower = CGRect(x: 0.6, y: 0.72, width: 0.12, height: 0.2)
        let image = CGSize(width: 1920, height: 1080)
        let canvas = CGSize(width: 2000, height: 500)
        let expected = ArtworkFraming(imageSize: image, canvasSize: canvas, faces: [highest])
        for faces in [[highest, lower], [lower, highest]] {
            let framing = ArtworkFraming(imageSize: image, canvasSize: canvas, faces: faces)
            XCTAssertEqual(framing.imageFrame, expected.imageFrame)
            XCTAssertFalse(framing.needsEdgeExtension)
            XCTAssertEqual(framing.imageFrame.width, 2000, accuracy: 0.01)
            let displayed = displayedRect(highest, framing: framing)
            XCTAssertGreaterThanOrEqual(displayed.minY, 0)
            XCTAssertLessThanOrEqual(displayed.maxY, canvas.height)
            XCTAssertGreaterThan(displayedRect(lower, framing: framing).maxY, canvas.height)
        }
    }

    func testHighestHeadIncludesHairMarginNotJustFaceTop() {
        let smallFace = CGRect(x: 0.2, y: 0.15, width: 0.03, height: 0.06)
        let largeHead = CGRect(x: 0.6, y: 0.18, width: 0.12, height: 0.24)
        let image = CGSize(width: 3840, height: 2160)
        let canvas = CGSize(width: 1920, height: 520)
        let framing = ArtworkFraming(imageSize: image, canvasSize: canvas, faces: [smallFace, largeHead])
        let expected = ArtworkFraming(imageSize: image, canvasSize: canvas, faces: [largeHead])
        XCTAssertEqual(framing.imageFrame, expected.imageFrame)
    }

    func testFacesNeverCauseAdditionalZoom() {
        let image = CGSize(width: 1920, height: 1080)
        let canvas = CGSize(width: 2000, height: 600)
        let framing = ArtworkFraming(imageSize: image, canvasSize: canvas,
                                     faces: [CGRect(x: 0.6, y: 0.4, width: 0.03, height: 0.05)])
        XCTAssertLessThanOrEqual(framing.imageFrame.width, 2000.001)
    }

    func testPachinkoGroupPortraitDoesNotExposeBlurredGutter() {
        // Actual detections from the cached 3840x2160 Pachinko backdrop.
        let faces = [CGRect(x: 0.20026, y: 0.33463, width: 0.06130, height: 0.10898),
                     CGRect(x: 0.34719, y: 0.17701, width: 0.18036, height: 0.32064),
                     CGRect(x: 0.32916, y: 0.51859, width: 0.03199, height: 0.05688),
                     CGRect(x: 0.83162, y: 0.43541, width: 0.05157, height: 0.09169),
                     CGRect(x: 0.70571, y: 0.41610, width: 0.04771, height: 0.08483),
                     CGRect(x: 0.08569, y: 0.57525, width: 0.03434, height: 0.06105),
                     CGRect(x: 0.67112, y: 0.50557, width: 0.03327, height: 0.05915)]
        let canvas = CGSize(width: 2128, height: 1077)
        let framing = ArtworkFraming(imageSize: CGSize(width: 3840, height: 2160),
                                     canvasSize: canvas, faces: faces)
        XCTAssertFalse(framing.needsEdgeExtension)
        XCTAssertEqual(framing.imageFrame.width, canvas.width, accuracy: 0.01)
        XCTAssertEqual(framing.imageFrame.minX, 0, accuracy: 0.01)
        for face in faces {
            let displayed = displayedRect(face, framing: framing)
            XCTAssertGreaterThanOrEqual(displayed.minY, 0)
            XCTAssertLessThanOrEqual(displayed.maxY, canvas.height)
        }
    }

    func testTedUltrawidePreservesHighestHeadWithoutShrinking() {
        let faces = [CGRect(x: 0.44673, y: 0.44399, width: 0.06846, height: 0.12171),
                     CGRect(x: 0.34095, y: 0.21632, width: 0.06140, height: 0.10915),
                     CGRect(x: 0.60640, y: 0.13148, width: 0.06168, height: 0.10965),
                     CGRect(x: 0.47207, y: 0.11431, width: 0.06133, height: 0.10903)]
        let canvas = CGSize(width: 1920, height: 520)
        let framing = ArtworkFraming(imageSize: CGSize(width: 3840, height: 2160),
                                     canvasSize: canvas, faces: faces)
        XCTAssertEqual(framing.imageFrame.width, canvas.width, accuracy: 0.01)
        XCTAssertFalse(framing.needsEdgeExtension)
        let highest = faces[3]
        let displayed = displayedRect(highest, framing: framing)
        XCTAssertGreaterThanOrEqual(displayed.minY, 0)
        XCTAssertLessThanOrEqual(displayed.maxY, canvas.height)
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
