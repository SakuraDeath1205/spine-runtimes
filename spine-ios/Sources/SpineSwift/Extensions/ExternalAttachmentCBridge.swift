import Foundation
import SpineC

public extension TextureRegion {
    func setRendererObjectTextureIndex(_ textureIndex: Int) {
        spine_ext_texture_region_set_renderer_object(
            _ptr.assumingMemoryBound(to: spine_texture_region_wrapper.self),
            UnsafeMutableRawPointer(bitPattern: textureIndex)
        )
    }
}

public extension AtlasPage {
    func setTextureIndex(_ textureIndex: Int) {
        spine_ext_atlas_page_set_texture(
            _ptr.assumingMemoryBound(to: spine_atlas_page_wrapper.self),
            UnsafeMutableRawPointer(bitPattern: textureIndex)
        )
    }
}

public extension Sequence {
    func setSingleRegionAndUpdate(
        _ region: TextureRegion,
        attachment: RegionAttachment
    ) {
        spine_ext_sequence_set_single_region_and_update(
            _ptr.assumingMemoryBound(to: spine_sequence_wrapper.self),
            attachment._ptr.assumingMemoryBound(to: spine_region_attachment_wrapper.self),
            region._ptr.assumingMemoryBound(to: spine_texture_region_wrapper.self)
        )
    }
}

public extension Sequence {
    @nonobjc
    func setSingleRegionAndUpdate(
        _ region: TextureRegion,
        attachment: MeshAttachment
    ) {
        spine_ext_sequence_set_single_region_and_update_mesh(
            _ptr.assumingMemoryBound(to: spine_sequence_wrapper.self),
            attachment._ptr.assumingMemoryBound(to: spine_mesh_attachment_wrapper.self),
            region._ptr.assumingMemoryBound(to: spine_texture_region_wrapper.self)
        )
    }
}
