import Foundation
import SpineSwift
import SpineShadersStructs

enum SpineRenderItem {
    case spine(RenderCommand)
    case embeddedSpine(SpineEmbeddedDraw)
}

/// A batch of already-transformed vertices to draw with a resolved texture index.
///
/// Used both for embedded child skeletons (vertices transformed into parent space)
/// and for slot texture anchors (a single textured quad at the anchor bone).
struct SpineEmbeddedDraw {
    let anchorSlotIndex: Int32
    let vertices: [SpineVertex]
    let textureIndex: Int
    let blendMode: BlendMode
}

