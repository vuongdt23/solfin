import SwiftUI
import PlaybackEngine

/// Holds image and analysis together, so the first visible frame is already
/// composed correctly rather than jumping after face detection completes.
struct FaceAwareHeroArtwork: View {
    let url: URL?
    let size: CGSize
    @State private var artwork: LoadedArtwork?

    private struct LoadedArtwork {
        let image: NSImage
        let faces: [CGRect]
    }

    var body: some View {
        SolfinDesign.spaceBlack
            .overlay {
                if let artwork {
                    let framing = ArtworkFraming(imageSize: artwork.image.size,
                                                 canvasSize: size, faces: artwork.faces)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: artwork.image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: framing.imageFrame.width, height: framing.imageFrame.height)
                            .mask {
                                // A contained portrait should blend into the dark copy
                                // area, not end at a hard boundary over a blurred duplicate.
                                let horizontalFeather = min(0.15, 160 / max(1, framing.imageFrame.width))
                                let verticalFeather = min(0.15, 120 / max(1, framing.imageFrame.height))
                                LinearGradient(stops: [
                                    .init(color: framing.imageFrame.minX > 1 ? .clear : .white, location: 0),
                                    .init(color: .white, location: horizontalFeather),
                                    .init(color: .white, location: 1 - horizontalFeather),
                                    .init(color: framing.imageFrame.maxX < size.width - 1 ? .clear : .white, location: 1)
                                ], startPoint: .leading, endPoint: .trailing)
                                .mask {
                                    LinearGradient(stops: [
                                        .init(color: framing.imageFrame.minY > 1 ? .clear : .white, location: 0),
                                        .init(color: .white, location: verticalFeather),
                                        .init(color: .white, location: 1 - verticalFeather),
                                        .init(color: framing.imageFrame.maxY < size.height - 1 ? .clear : .white, location: 1)
                                    ], startPoint: .top, endPoint: .bottom)
                                }
                            }
                            .offset(x: framing.imageFrame.minX, y: framing.imageFrame.minY)
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .task(id: url) {
                artwork = nil
                guard let url else { return }
                async let image = MediaAssetCache.shared.image(for: url)
                async let analysis = ArtworkFaceCache.shared.analysis(for: url)
                let loaded = await (image, analysis)
                guard !Task.isCancelled, let image = loaded.0 else { return }
                artwork = LoadedArtwork(image: image, faces: loaded.1?.faces ?? [])
            }
    }
}
