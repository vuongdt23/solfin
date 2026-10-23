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
                        if framing.needsEdgeExtension {
                            Image(nsImage: artwork.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size.width, height: size.height)
                                .clipped()
                                .blur(radius: 36)
                                .overlay(.black.opacity(0.3))
                        }
                        Image(nsImage: artwork.image)
                            .resizable()
                            .frame(width: framing.imageFrame.width, height: framing.imageFrame.height)
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
