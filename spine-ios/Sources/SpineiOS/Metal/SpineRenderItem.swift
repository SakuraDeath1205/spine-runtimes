import Foundation
import Metal
import SpineSwift

enum SpineRenderItem {
    case spine(RenderCommand)
    case externalTexture(SpineExternalTexture)
}

struct SpineExternalTexture {
    let anchorSlotIndex: Int32
    let texture: MTLTexture
    let width: Float
    let height: Float
    let offsetX: Float
    let offsetY: Float
}
