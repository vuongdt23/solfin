import Foundation

/// Shelf bounds always follow the usable window width, including ultrawide
/// windows. Artwork can have its own size limits; a scrolling viewport must not.
enum HomeShelfGeometry {
    static func contentWidth(viewport: CGFloat, leadingInset: CGFloat, trailingInset: CGFloat = 32) -> CGFloat {
        max(1, viewport - leadingInset - trailingInset)
    }

    static func targetX(current: CGFloat, delta: CGFloat, documentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        min(max(0, current - delta), max(0, documentWidth - viewportWidth))
    }
}
