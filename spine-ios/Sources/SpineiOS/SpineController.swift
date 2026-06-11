/******************************************************************************
 * Spine Runtimes License Agreement
 * Last updated April 5, 2025. Replaces all prior versions.
 *
 * Copyright (c) 2013-2025, Esoteric Software LLC
 *
 * Integration of the Spine Runtimes into software or otherwise creating
 * derivative works of the Spine Runtimes is permitted under the terms and
 * conditions of Section 2 of the Spine Editor License Agreement:
 * http://esotericsoftware.com/spine-editor-license
 *
 * Otherwise, it is permitted to integrate the Spine Runtimes into software
 * or otherwise create derivative works of the Spine Runtimes (collectively,
 * "Products"), provided that each user of the Products must obtain their own
 * Spine Editor license and redistribution of the Products in any form must
 * include this license and copyright notice.
 *
 * THE SPINE RUNTIMES ARE PROVIDED BY ESOTERIC SOFTWARE LLC "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL ESOTERIC SOFTWARE LLC BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES,
 * BUSINESS INTERRUPTION, OR LOSS OF USE, DATA, OR PROFITS) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THE SPINE RUNTIMES, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *****************************************************************************/

import CoreGraphics
import Foundation
import QuartzCore
import SpineSwift
import UIKit
import simd
import SpineShadersStructs

public typealias SpineControllerCallback = (_ controller: SpineController) -> Void

/// Controls how the skeleton of a ``SpineUIView`` is animated and rendered.
///
/// Upon initialization of a ``SpineUIView`` the provided `onInitialized` callback method is called once. This method can be used
/// to setup the initial animation(s) of the skeleton, among other things.
///
/// After initialization is complete, the ``SpineUIView`` is rendered at the screen refresh rate. In each frame,
/// the ``AnimationState`` is updated and applied to the ``Skeleton``.
///
/// Next the optionally provided method `onBeforeUpdateWorldTransforms` is called, which can modify the
/// skeleton before its current pose is calculated using ``Skeleton/updateWorldTransform(physics:)``. After
/// ``Skeleton.updateWorldTransforms`` has completed, the optional `onAfterUpdateWorldTransforms` method is
/// called, which can modify the current pose before rendering the skeleton.
///
/// Before the skeleton's current pose is rendered by the ``SpineUIView`` the optional `onBeforePaint` is called,
/// which allows rendering backgrounds or other objects that should go behind the skeleton in your view hierarchy. The
/// ``SpineUIView`` then renderes the skeleton's current pose, and finally calls the optional `onAfterPaint`, after which you
/// can render additional objects on top of the skeleton in your view hierarchy.
///
/// The underlying ``Atlas``, ``SkeletonData``, ``Skeleton``, ``AnimationStateData``, ``AnimationState``, and ``SkeletonDrawable``
/// can be accessed through their respective getters to inspect and/or modify the skeleton and its associated data. Accessing
/// this data is only allowed if the ``SpineUIView`` and its data have been initialized and have not been disposed yet.
///
/// By default, the view updates and renders the skeleton every frame. The `pause` method can be used to pause updating
/// and rendering the skeleton. The `resume` method resumes updating and rendering the skeleton. The `isPlaying` property
/// reports the current state.
///
/// Per default, ``SkeletonDrawableWrapper`` is disposed when ``SpineController`` is deinitialized. You can disable this behaviour with the ``disposeDrawableOnDeInit`` contructor parameter.
@objcMembers
public final class SpineController: NSObject, ObservableObject {

    public internal(set) var drawable: SkeletonDrawableWrapper!

    private let onInitialized: SpineControllerCallback?
    private let onBeforeUpdateWorldTransforms: SpineControllerCallback?
    private let onAfterUpdateWorldTransforms: SpineControllerCallback?
    private let onBeforePaint: SpineControllerCallback?
    private let onAfterPaint: SpineControllerCallback?
    private let disposeDrawableOnDeInit: Bool

    private var scaleX: CGFloat = 1
    private var scaleY: CGFloat = 1
    private var offsetX: CGFloat = 0
    private var offsetY: CGFloat = 0

    internal weak var renderer: SpineRenderer?
    private var externalAttachmentStore: [String: ExternalAttachmentHandle] = [:]
    public var slotTextureAnchors: [String: SpineSlotTextureAnchor] = [:]

    /// Child skeletons embedded in-pass at an anchor slot, keyed by slot name.
    public var slotSpineAnchors: [String: SpineSlotSpineAnchor] = [:]

    @Published
    public private(set) var isPlaying: Bool = true

    @Published
    public private(set) var viewSize: CGSize = .zero

    /// Constructs a new ``SpineUIview`` controller. See the class documentation of ``SpineWidgetController`` for information on
    /// the optional arguments.
    public init(
        onInitialized: SpineControllerCallback? = nil,
        onBeforeUpdateWorldTransforms: SpineControllerCallback? = nil,
        onAfterUpdateWorldTransforms: SpineControllerCallback? = nil,
        onBeforePaint: SpineControllerCallback? = nil,
        onAfterPaint: SpineControllerCallback? = nil,
        disposeDrawableOnDeInit: Bool = true
    ) {
        self.onInitialized = onInitialized
        self.onBeforeUpdateWorldTransforms = onBeforeUpdateWorldTransforms
        self.onAfterUpdateWorldTransforms = onAfterUpdateWorldTransforms
        self.onBeforePaint = onBeforePaint
        self.onAfterPaint = onAfterPaint
        self.disposeDrawableOnDeInit = disposeDrawableOnDeInit

        super.init()
    }

    deinit {
        if disposeDrawableOnDeInit {
            drawable?.dispose()  // TODO move drawable out of view?
        }
    }

    /// Manually dispose the drawable. Call this when you know the controller is no longer needed.
    /// This is useful in SwiftUI where views may be cached and deinit may be delayed.
    public func dispose() {
        drawable?.dispose()
        drawable = nil
    }

    /// The ``Atlas`` from which images to render the skeleton are sourced.
    public var atlas: Atlas {
        drawable.atlas
    }

    /// The setup-pose data used by the skeleton.
    public var skeletonData: SkeletonData {
        drawable.skeletonData
    }

    /// The ``Skeleton``
    public var skeleton: Skeleton {
        drawable.skeleton
    }

    /// The mixing information used by the ``AnimationState``
    public var animationStateData: AnimationStateData {
        drawable.animationStateData
    }

    /// The ``AnimationState`` used to manage animations that are being applied to the
    /// skeleton.
    public var animationState: AnimationState {
        drawable.animationState
    }


    /// Transforms the coordinates given in the ``SpineUIView`` coordinate system in `position` to
    /// the skeleton coordinate system. See the `IKFollowing.swift` example how to use this
    /// to move a bone based on user touch input.
    public func toSkeletonCoordinates(position: CGPoint) -> CGPoint {
        let x = position.x
        let y = position.y
        return CGPoint(
            x: (x - viewSize.width / 2) / scaleX - offsetX,
            y: (y - viewSize.height / 2) / scaleY - offsetY
        )
    }

    /// Transforms the coordinates given in skeleton coordinate system to
    /// the the ``SpineUIView`` coordinates. See the `DebugRendering.swift` example hot to use this to draw rectangles over skeleton bones for debugging purposes.
    public func fromSkeletonCoordinates(position: CGPoint) -> CGPoint {
        let x = position.x
        let y = position.y
        return CGPoint(
            x: (x + offsetX) * scaleX,
            y: (y + offsetY) * scaleY
        )
    }

    /// Pauses updating and rendering the skeleton.
    public func pause() {
        isPlaying = false
    }

    /// Resumes updating and rendering the skeleton.
    public func resume() {
        isPlaying = true
    }

    internal func load(atlasFile: String, skeletonFile: String, bundle: Bundle = .main) async throws {
        let atlasAndPages = try await Atlas.fromBundle(atlasFile, bundle: bundle)
        let skeletonData = try await SkeletonData.fromBundle(
            atlas: atlasAndPages.0,
            skeletonFileName: skeletonFile,
            bundle: bundle
        )
        try await MainActor.run {
            let skeletonDrawableWrapper = try SkeletonDrawableWrapper(
                atlas: atlasAndPages.0,
                atlasPages: atlasAndPages.1,
                skeletonData: skeletonData
            )
            self.drawable = skeletonDrawableWrapper
        }
    }

    internal func initialize() {
        onInitialized?(self)
    }

    private func retainExternalAttachment(
        slotName: String,
        attachment: Attachment,
        region: TextureRegion,
        images: [UIImage],
        atlas: Atlas?,
        textureIndices: [Int]
    ) {
        externalAttachmentStore[slotName] = ExternalAttachmentHandle(
            attachment: attachment,
            region: region,
            images: images,
            atlas: atlas,
            textureIndices: textureIndices
        )
    }
}

extension SpineController: SpineRendererDelegate {

    func spineRendererWillDraw(_ spineRenderer: SpineRenderer) {
        onBeforePaint?(self)
    }

    func spineRendererDidDraw(_ spineRenderer: SpineRenderer) {
        onAfterPaint?(self)
    }

    func spineRendererDidUpdate(_ spineRenderer: SpineRenderer, scaleX: CGFloat, scaleY: CGFloat, offsetX: CGFloat, offsetY: CGFloat, size: CGSize) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.viewSize = size
    }
}

extension SpineController: SpineRendererDataSource {

    func spineRendererWillUpdate(_ spineRenderer: SpineRenderer) {
        onBeforeUpdateWorldTransforms?(self)
    }

    func spineRendererDidUpdate(_ spineRenderer: SpineRenderer) {
        onAfterUpdateWorldTransforms?(self)
    }

    func spineRenderer(_ spineRenderer: SpineRenderer, needsUpdate delta: TimeInterval) {
        drawable?.update(delta: Float(delta))

        // Advance every embedded child skeleton with the same delta so their
        // animations stay in sync with the parent.
        for anchor in slotSpineAnchors.values {
            anchor.childDrawable.update(delta: Float(delta))
        }
    }

    func isPlaying(_ spineRenderer: SpineRenderer) -> Bool {
        return isPlaying
    }

    func skeletonDrawable(_ spineRenderer: SpineRenderer) -> SkeletonDrawableWrapper {
        return drawable
    }

    // func renderCommands(_ spineRenderer: SpineRenderer) -> [RenderCommand] {
    //     guard let drawable = drawable else { return [] }

    //     var commands = [RenderCommand]()
    //     var current = drawable.skeletonDrawable.renderUnbatched()
    //     while let cmd = current {
    //         print("slotIndex:", cmd.slotIndex)
    //         commands.append(cmd)
    //         current = cmd.next
    //     }
    //     return commands
    // }
    func renderItems(_ spineRenderer: SpineRenderer) -> [SpineRenderItem] {
        guard let drawable = drawable else {
            return []
        }

        var items = [SpineRenderItem]()
        var current = drawable.skeletonDrawable.renderUnbatched()

        var anchorsBySlotIndex = [Int32: SpineSlotTextureAnchor]()

        for anchor in slotTextureAnchors.values {
            if let slot = skeleton.findSlot(anchor.slotName) {
                anchorsBySlotIndex[slot.data.index] = anchor
            }
        }

        var spineAnchorsBySlotIndex = [Int32: SpineSlotSpineAnchor]()

        for anchor in slotSpineAnchors.values {
            if let slot = skeleton.findSlot(anchor.slotName) {
                spineAnchorsBySlotIndex[slot.data.index] = anchor
            }
        }

        while let command = current {
            // Slot texture anchor: emit a single textured quad at the anchor bone's
            // world position. Routed through `.embeddedSpine` so it shares the same
            // vertex/texture-index draw path as embedded child skeletons. The texture
            // was registered into the parent renderer at `setSlotTextureAnchor` time.
            if let anchor = anchorsBySlotIndex[command.slotIndex],
               let anchorSlot = skeleton.findSlot(anchor.slotName) {
                let bone = anchorSlot.bone
                let centerX = bone.appliedPose.worldX + anchor.offsetX
                let centerY = bone.appliedPose.worldY + anchor.offsetY

                let quad = Self.makeTexturedQuad(
                    centerX: centerX,
                    centerY: centerY,
                    width: anchor.width,
                    height: anchor.height
                )

                items.append(
                    .embeddedSpine(
                        SpineEmbeddedDraw(
                            anchorSlotIndex: command.slotIndex,
                            vertices: quad,
                            textureIndex: anchor.textureIndex,
                            blendMode: .normal
                        )
                    )
                )
            }

            // Embed a child skeleton at this slot. Each child render command's
            // vertices are transformed from child-skeleton space into parent
            // skeleton space around the anchor bone's current world position,
            // scaled by `scale`. The child's texture index was baked into the
            // command when its atlas pages were registered with the renderer.
            if let spineAnchor = spineAnchorsBySlotIndex[command.slotIndex],
               let anchorSlot = skeleton.findSlot(spineAnchor.slotName) {
                let bone = anchorSlot.bone
                let anchorX = bone.appliedPose.worldX + spineAnchor.offsetX
                let anchorY = bone.appliedPose.worldY + spineAnchor.offsetY

                var childCommand = spineAnchor.childDrawable.skeletonDrawable.renderUnbatched()

                while let child = childCommand {
                    var vertices = Array(child.getVertices())

                    for i in vertices.indices {
                        let position = vertices[i].position
                        vertices[i].position = SIMD2<Float>(
                            anchorX + position.x * spineAnchor.scale,
                            anchorY + position.y * spineAnchor.scale
                        )
                    }

                    items.append(
                        .embeddedSpine(
                            SpineEmbeddedDraw(
                                anchorSlotIndex: command.slotIndex,
                                vertices: vertices,
                                textureIndex: Int(bitPattern: child.texture),
                                blendMode: child.blendMode
                            )
                        )
                    )

                    childCommand = child.next
                }
            }

            items.append(.spine(command))
            current = command.next
        }

        return items
    }

    /// Builds two triangles (6 vertices) for a texture quad centered at
    /// `(centerX, centerY)` in skeleton space, sized `width` x `height`. UVs are
    /// v-flipped so the image renders upright in Spine's y-up coordinate system.
    /// Vertex color is opaque white and bleach is 0 so the texture renders untinted.
    private static func makeTexturedQuad(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float
    ) -> [SpineVertex] {
        let halfW = width / 2
        let halfH = height / 2

        let left = centerX - halfW
        let right = centerX + halfW
        let bottom = centerY - halfH
        let top = centerY + halfH

        let white = simd_float4(1, 1, 1, 1)

        func vertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float) -> SpineVertex {
            SpineVertex(
                position: simd_float2(x, y),
                color: white,
                uv: simd_float2(u, v),
                bleach: 0
            )
        }

        let topLeft = vertex(left, top, 0, 0)
        let topRight = vertex(right, top, 1, 0)
        let bottomLeft = vertex(left, bottom, 0, 1)
        let bottomRight = vertex(right, bottom, 1, 1)

        return [
            topLeft, bottomLeft, topRight,
            topRight, bottomLeft, bottomRight,
        ]
    }
}

// MARK: ExternalAttachment
private final class ExternalAttachmentHandle {
    let attachment: Attachment
    let region: TextureRegion
    let images: [UIImage]
    let atlas: Atlas?
    let textureIndices: [Int]

    init(
        attachment: Attachment,
        region: TextureRegion,
        images: [UIImage],
        atlas: Atlas?,
        textureIndices: [Int]
    ) {
        self.attachment = attachment
        self.region = region
        self.images = images
        self.atlas = atlas
        self.textureIndices = textureIndices
    }
}

public enum SpineExternalAttachmentError: Error {
    case rendererNotReady
    case imageNotFound(String)
    case invalidImage
    case slotNotFound(String)
    case attachmentNotFound(slot: String, attachment: String?)
    case templateIsNotRegionAttachment(String)
    case templateIsNotRenderableAttachment(String)

    case atlasFileNotFound(String)
    case invalidAtlasString(String)
    case atlasHasNoPages(String)
    case atlasPageNotFound
    case atlasPageImageCountMismatch(pages: Int, images: Int)
    case atlasRegionNotFound(String)
    case atlasRegionNameRequired
    case singlePageImageOverrideUsedForMultiPageAtlas(pageCount: Int)

    case slotNameRequiredForPngOnly
    case regionNameRequiresSlot
    case noMatchingSlotsForAtlas(String)
}

private struct AtlasReplacementTarget {
    let slotName: String
    let slot: Slot
    let template: Attachment
    let region: AtlasRegion
}

extension SpineController {
    private func applyTextureRegionToCopiedAttachment(
        template: Attachment,
        region: TextureRegion,
        path: String,
        imageSize: CGSize?,
        keepTemplateSize: Bool
    ) throws -> Attachment {
        if let regionTemplate = template as? RegionAttachment {
            let copied = regionTemplate.copyAttachment() as! RegionAttachment

            copied.path = path

            if !keepTemplateSize, let imageSize {
                copied.width = Float(imageSize.width)
                copied.height = Float(imageSize.height)
            }

            copied.sequence.setSingleRegionAndUpdate(
                region,
                attachment: copied
            )

            return copied
        }

        if let meshTemplate = template as? MeshAttachment {
            let copied = meshTemplate.copyAttachment() as! MeshAttachment

            copied.path = path

            copied.sequence.setSingleRegionAndUpdate(
                region,
                attachment: copied
            )

            return copied
        }

        throw SpineExternalAttachmentError.templateIsNotRenderableAttachment(
            template.name
        )
    }

    @MainActor
    @discardableResult
    public func replaceExternalRegionAttachment(
        slotName: String? = nil,
        pngFileName: String,
        atlasFileName: String? = nil,
        regionName: String? = nil,
        templateAttachmentName: String? = nil,
        bundle: Bundle = .main,
        keepTemplateSize: Bool = true
    ) async throws -> [String] {
        if let atlasFileName {
            return try await replaceRegionAttachmentFromAtlas(
                slotName: slotName,
                atlasFileName: atlasFileName,
                regionName: regionName,
                pageImageFileNameOverride: pngFileName,
                templateAttachmentName: templateAttachmentName,
                bundle: bundle,
                keepTemplateSize: keepTemplateSize
            )
        }

        guard let slotName else {
            throw SpineExternalAttachmentError.slotNameRequiredForPngOnly
        }

        try await replaceRegionAttachment(
            slotName: slotName,
            pngFileName: pngFileName,
            templateAttachmentName: templateAttachmentName,
            bundle: bundle,
            keepTemplateSize: keepTemplateSize
        )

        return [slotName]
    }

    @MainActor
    public func replaceRegionAttachment(
        slotName: String,
        pngFileName: String,
        templateAttachmentName: String? = nil,
        bundle: Bundle = .main,
        keepTemplateSize: Bool = true
    ) async throws {
        guard let renderer else {
            throw SpineExternalAttachmentError.rendererNotReady
        }

        guard let slot = skeleton.findSlot(slotName) else {
            throw SpineExternalAttachmentError.slotNotFound(slotName)
        }

        let template = try resolveTemplateRenderableAttachment(
            slotName: slotName,
            slot: slot,
            templateAttachmentName: templateAttachmentName,
            matchedRegionName: nil
        )

        let image = try Self.loadImage(
            pngFileName,
            bundle: bundle
        )

        guard let cgImage = image.cgImage else {
            throw SpineExternalAttachmentError.invalidImage
        }

        let textureIndex = try renderer.registerTexture(image)

        let runtimeRegion = TextureRegion()
        runtimeRegion.u = 0
        runtimeRegion.v = 0
        runtimeRegion.u2 = 1
        runtimeRegion.v2 = 1
        runtimeRegion.regionWidth = Int32(cgImage.width)
        runtimeRegion.regionHeight = Int32(cgImage.height)
        runtimeRegion.setRendererObjectTextureIndex(textureIndex)

        let copied = try applyTextureRegionToCopiedAttachment(
            template: template,
            region: runtimeRegion,
            path: pngFileName,
            imageSize: CGSize(
                width: cgImage.width,
                height: cgImage.height
            ),
            keepTemplateSize: keepTemplateSize
        )

        slot.pose.attachment = copied
        slot.appliedPose.attachment = copied

        retainExternalAttachment(
            slotName: slotName,
            attachment: copied,
            region: runtimeRegion,
            images: [image],
            atlas: nil,
            textureIndices: [textureIndex]
        )
    }

    @MainActor
    @discardableResult
    public func replaceRegionAttachmentFromAtlas(
        slotName: String? = nil,
        atlasFileName: String,
        regionName: String? = nil,
        pageImageFileNameOverride: String? = nil,
        templateAttachmentName: String? = nil,
        bundle: Bundle = .main,
        keepTemplateSize: Bool = true
    ) async throws -> [String] {
        guard let renderer else {
            throw SpineExternalAttachmentError.rendererNotReady
        }

        let atlasAndImages = try await Self.loadAtlasAndPageImages(
            atlasFileName: atlasFileName,
            pageImageFileNameOverride: pageImageFileNameOverride,
            bundle: bundle
        )

        let runtimeAtlas = atlasAndImages.atlas
        let pageImages = atlasAndImages.images
        let textureIndices = try renderer.registerTextures(pageImages)

        try Self.bindAtlasPagesAndRegions(
            atlas: runtimeAtlas,
            textureIndices: textureIndices
        )

        if let slotName {
            guard let slot = skeleton.findSlot(slotName) else {
                throw SpineExternalAttachmentError.slotNotFound(slotName)
            }

            let template = try resolveTemplateRenderableAttachment(
                slotName: slotName,
                slot: slot,
                templateAttachmentName: templateAttachmentName,
                matchedRegionName: regionName
            )

            let selectedRegion = try Self.resolveAtlasRegion(
                atlas: runtimeAtlas,
                regionName: regionName,
                template: template
            )

            try applyAtlasReplacement(
                slotName: slotName,
                slot: slot,
                template: template,
                region: selectedRegion,
                runtimeAtlas: runtimeAtlas,
                pageImages: pageImages,
                textureIndices: textureIndices,
                keepTemplateSize: keepTemplateSize
            )

            return [slotName]
        }

        if regionName != nil {
            throw SpineExternalAttachmentError.regionNameRequiresSlot
        }

        let targets = try collectAtlasReplacementTargets(
            atlas: runtimeAtlas,
            templateAttachmentName: templateAttachmentName
        )

        guard !targets.isEmpty else {
            throw SpineExternalAttachmentError.noMatchingSlotsForAtlas(atlasFileName)
        }

        for target in targets {
            try applyAtlasReplacement(
                slotName: target.slotName,
                slot: target.slot,
                template: target.template,
                region: target.region,
                runtimeAtlas: runtimeAtlas,
                pageImages: pageImages,
                textureIndices: textureIndices,
                keepTemplateSize: keepTemplateSize
            )
        }

        return targets.map { $0.slotName }
    }

    private func collectAtlasReplacementTargets(
        atlas: Atlas,
        templateAttachmentName: String?
    ) throws -> [AtlasReplacementTarget] {
        let regions = atlas.regions
        var targets: [AtlasReplacementTarget] = []
        var usedSlotNames = Set<String>()
        var matchedRegionIndices = Set<Int>()

        /*
         第一轮：严格优先 region.name 匹配 slot.data.name。
         例如 atlas 里有 Toufa_Zhong，Skeleton 里也有 slot Toufa_Zhong，
         这种是最明确的对应关系，优先处理。
         */
        for index in 0..<regions.count {
            guard let region = regions[index] else {
                continue
            }

            guard !region.name.isEmpty else {
                continue
            }

            if let target = try resolveExactSlotTarget(
                for: region,
                templateAttachmentName: templateAttachmentName,
                usedSlotNames: usedSlotNames
            ) {
                targets.append(target)
                usedSlotNames.insert(target.slotName)
                matchedRegionIndices.insert(index)
            }
        }

        /*
         第二轮：没有直接同名 slot 的 region，
         再尝试匹配当前 attachment.path、attachment.name、setup attachmentName，
         或 skeleton.getAttachment(slotName, region.name)。
         */
        for index in 0..<regions.count {
            if matchedRegionIndices.contains(index) {
                continue
            }

            guard let region = regions[index] else {
                continue
            }

            guard !region.name.isEmpty else {
                continue
            }

            if let target = try resolveCompatibleSlotTarget(
                for: region,
                templateAttachmentName: templateAttachmentName,
                usedSlotNames: usedSlotNames
            ) {
                targets.append(target)
                usedSlotNames.insert(target.slotName)
                matchedRegionIndices.insert(index)
            }
        }

        return targets
    }

    private func resolveExactSlotTarget(
        for region: AtlasRegion,
        templateAttachmentName: String?,
        usedSlotNames: Set<String>
    ) throws -> AtlasReplacementTarget? {
        let regionNameCandidates = Self.nameCandidates(for: region.name)

        for candidate in regionNameCandidates {
            guard let slot = skeleton.findSlot(candidate) else {
                continue
            }

            let slotName = slot.data.name

            if usedSlotNames.contains(slotName) {
                continue
            }

            let template = try resolveTemplateRenderableAttachment(
                slotName: slotName,
                slot: slot,
                templateAttachmentName: templateAttachmentName,
                matchedRegionName: region.name
            )

            return AtlasReplacementTarget(
                slotName: slotName,
                slot: slot,
                template: template,
                region: region
            )
        }

        return nil
    }

    private func resolveCompatibleSlotTarget(
        for region: AtlasRegion,
        templateAttachmentName: String?,
        usedSlotNames: Set<String>
    ) throws -> AtlasReplacementTarget? {
        let regionNameCandidates = Self.nameCandidates(for: region.name)
        let slots = skeleton.slots

        for index in 0..<slots.count {
            guard let slot = slots[index] else {
                continue
            }

            let slotName = slot.data.name

            if usedSlotNames.contains(slotName) {
                continue
            }

            let matchesBySlotPose = Self.slot(
                slot,
                matchesAnyRegionNameCandidate: regionNameCandidates
            )

            let matchesBySkeletonAttachment = hasAttachment(
                slotName: slotName,
                attachmentNameCandidates: regionNameCandidates
            )

            guard matchesBySlotPose || matchesBySkeletonAttachment else {
                continue
            }

            let template = try resolveTemplateRenderableAttachment(
                slotName: slotName,
                slot: slot,
                templateAttachmentName: templateAttachmentName,
                matchedRegionName: region.name
            )

            return AtlasReplacementTarget(
                slotName: slotName,
                slot: slot,
                template: template,
                region: region
            )
        }

        return nil
    }

    private func hasAttachment(
        slotName: String,
        attachmentNameCandidates: [String]
    ) -> Bool {
        for attachmentName in attachmentNameCandidates {
            if skeleton.getAttachment(slotName, attachmentName) != nil {
                return true
            }
        }

        return false
    }

    private static func slot(
        _ slot: Slot,
        matchesAnyRegionNameCandidate regionNameCandidates: [String]
    ) -> Bool {
        let slotCandidates = slotMatchCandidateNames(for: slot)

        for slotCandidate in slotCandidates {
            for regionCandidate in regionNameCandidates {
                if slotCandidate == regionCandidate {
                    return true
                }
            }
        }

        return false
    }

    private static func slotMatchCandidateNames(for slot: Slot) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func appendCandidates(_ value: String) {
            for candidate in nameCandidates(for: value) {
                guard !candidate.isEmpty else {
                    continue
                }

                guard !seen.contains(candidate) else {
                    continue
                }

                seen.insert(candidate)
                result.append(candidate)
            }
        }

        let currentAttachment = slot.appliedPose.attachment ?? slot.pose.attachment

        if let currentRegionAttachment = currentAttachment as? RegionAttachment {
            appendCandidates(currentRegionAttachment.path)
        }

        if let currentMeshAttachment = currentAttachment as? MeshAttachment {
            appendCandidates(currentMeshAttachment.path)
        }

        if let currentAttachment {
            appendCandidates(currentAttachment.name)
        }

        appendCandidates(slot.data.attachmentName)
        appendCandidates(slot.data.name)

        return result
    }

    private static func nameCandidates(for rawName: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                return
            }

            guard !seen.contains(trimmed) else {
                return
            }

            seen.insert(trimmed)
            result.append(trimmed)
        }

        append(rawName)

        let nsRaw = rawName as NSString
        append(nsRaw.deletingPathExtension)

        let lastPathComponent = nsRaw.lastPathComponent
        append(lastPathComponent)

        let nsLastPathComponent = lastPathComponent as NSString
        append(nsLastPathComponent.deletingPathExtension)

        return result
    }

    private func resolveTemplateRenderableAttachment(
        slotName: String,
        slot: Slot,
        templateAttachmentName: String?,
        matchedRegionName: String?
    ) throws -> Attachment {
        if let templateAttachmentName {
            guard let attachment = skeleton.getAttachment(slotName, templateAttachmentName) else {
                throw SpineExternalAttachmentError.attachmentNotFound(
                    slot: slotName,
                    attachment: templateAttachmentName
                )
            }

            return try Self.validateRenderableAttachment(attachment)
        }

        if let current = slot.appliedPose.attachment ?? slot.pose.attachment {
            if current is RegionAttachment || current is MeshAttachment {
                return current
            }
        }

        if let matchedRegionName {
            let attachmentNameCandidates = Self.nameCandidates(for: matchedRegionName)

            for attachmentName in attachmentNameCandidates {
                guard let attachment = skeleton.getAttachment(slotName, attachmentName) else {
                    continue
                }

                return try Self.validateRenderableAttachment(attachment)
            }
        }

        let setupAttachmentName = slot.data.attachmentName

        if !setupAttachmentName.isEmpty,
        let attachment = skeleton.getAttachment(slotName, setupAttachmentName) {
            return try Self.validateRenderableAttachment(attachment)
        }

        throw SpineExternalAttachmentError.attachmentNotFound(
            slot: slotName,
            attachment: matchedRegionName ?? setupAttachmentName
        )
    }

    private static func validateRenderableAttachment(
        _ attachment: Attachment
    ) throws -> Attachment {
        if attachment is RegionAttachment || attachment is MeshAttachment {
            return attachment
        }

        throw SpineExternalAttachmentError.templateIsNotRenderableAttachment(
            attachment.name
        )
    }


    private func applyAtlasReplacement(
        slotName: String,
        slot: Slot,
        template: Attachment,
        region: AtlasRegion,
        runtimeAtlas: Atlas,
        pageImages: [UIImage],
        textureIndices: [Int],
        keepTemplateSize: Bool
    ) throws {
        let copied = try applyTextureRegionToCopiedAttachment(
            template: template,
            region: region,
            path: region.name,
            imageSize: nil,
            keepTemplateSize: keepTemplateSize
        )

        slot.pose.attachment = copied
        slot.appliedPose.attachment = copied

        retainExternalAttachment(
            slotName: slotName,
            attachment: copied,
            region: region,
            images: pageImages,
            atlas: runtimeAtlas,
            textureIndices: textureIndices
        )
    }

    private static func bundleOrFileURL(
        _ nameOrPath: String,
        bundle: Bundle,
        notFound: SpineExternalAttachmentError
    ) throws -> URL {
        let fileURL = URL(fileURLWithPath: nameOrPath)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        let nsName = nameOrPath as NSString
        let resourceName = nsName.deletingPathExtension
        let resourceExtension = nsName.pathExtension

        if !resourceName.isEmpty,
           !resourceExtension.isEmpty,
           let bundleURL = bundle.url(
                forResource: resourceName,
                withExtension: resourceExtension
           ) {
            return bundleURL
        }

        throw notFound
    }

    private static func loadImage(
        _ nameOrPath: String,
        bundle: Bundle
    ) throws -> UIImage {
        if let image = UIImage(
            named: nameOrPath,
            in: bundle,
            compatibleWith: nil
        ) {
            return image
        }

        let url = try bundleOrFileURL(
            nameOrPath,
            bundle: bundle,
            notFound: .imageNotFound(nameOrPath)
        )

        guard let image = UIImage(contentsOfFile: url.path) else {
            throw SpineExternalAttachmentError.invalidImage
        }

        return image
    }

    private static func loadAtlasAndPageImages(
        atlasFileName: String,
        pageImageFileNameOverride: String?,
        bundle: Bundle
    ) async throws -> (atlas: Atlas, images: [UIImage]) {
        if let pageImageFileNameOverride {
            let atlas = try loadAtlasOnly(
                atlasFileName,
                bundle: bundle
            )

            let pageCount = atlas.pages.count

            guard pageCount == 1 else {
                atlas.dispose()
                throw SpineExternalAttachmentError
                    .singlePageImageOverrideUsedForMultiPageAtlas(pageCount: pageCount)
            }

            let image = try loadImage(
                pageImageFileNameOverride,
                bundle: bundle
            )

            return (atlas, [image])
        }

        return try await Atlas.fromBundle(
            atlasFileName,
            bundle: bundle
        )
    }

    private static func loadAtlasOnly(
        _ atlasFileName: String,
        bundle: Bundle
    ) throws -> Atlas {
        let url = try bundleOrFileURL(
            atlasFileName,
            bundle: bundle,
            notFound: .atlasFileNotFound(atlasFileName)
        )

        let data = try Data(contentsOf: url)

        guard let atlasString = String(data: data, encoding: .utf8) else {
            throw SpineExternalAttachmentError.invalidAtlasString(atlasFileName)
        }

        return try loadAtlas(atlasString)
    }

    private static func bindAtlasPagesAndRegions(
        atlas: Atlas,
        textureIndices: [Int]
    ) throws {
        let pages = atlas.pages

        guard pages.count > 0 else {
            throw SpineExternalAttachmentError.atlasHasNoPages("")
        }

        guard pages.count == textureIndices.count else {
            throw SpineExternalAttachmentError.atlasPageImageCountMismatch(
                pages: pages.count,
                images: textureIndices.count
            )
        }

        let regions = atlas.regions

        for pageIndex in 0..<pages.count {
            guard let page = pages[pageIndex] else {
                throw SpineExternalAttachmentError.atlasPageNotFound
            }

            let textureIndex = textureIndices[pageIndex]

            page.setTextureIndex(textureIndex)

            for regionIndex in 0..<regions.count {
                guard
                    let region = regions[regionIndex],
                    let regionPage = region.page
                else {
                    continue
                }

                if regionPage._ptr == page._ptr {
                    region.setRendererObjectTextureIndex(textureIndex)
                }
            }
        }
    }

    private static func resolveAtlasRegion(
        atlas: Atlas,
        regionName: String?,
        template: Attachment
    ) throws -> AtlasRegion {
        if let regionName, !regionName.isEmpty {
            let regionNameCandidates = nameCandidates(for: regionName)

            for candidate in regionNameCandidates {
                if let region = atlas.findRegion(candidate) {
                    return region
                }
            }

            throw SpineExternalAttachmentError.atlasRegionNotFound(regionName)
        }

        if let templatePath = renderableAttachmentPath(template),
        !templatePath.isEmpty {
            let pathCandidates = nameCandidates(for: templatePath)

            for candidate in pathCandidates {
                if let region = atlas.findRegion(candidate) {
                    return region
                }
            }
        }

        let nameCandidates = nameCandidates(for: template.name)

        for candidate in nameCandidates {
            if let region = atlas.findRegion(candidate) {
                return region
            }
        }

        let regions = atlas.regions

        if regions.count == 1, let onlyRegion = regions[0] {
            return onlyRegion
        }

        throw SpineExternalAttachmentError.atlasRegionNameRequired
    }

    private static func renderableAttachmentPath(
        _ attachment: Attachment
    ) -> String? {
        if let regionAttachment = attachment as? RegionAttachment {
            return regionAttachment.path
        }

        if let meshAttachment = attachment as? MeshAttachment {
            return meshAttachment.path
        }

        return nil
    }

}

// MARK: Slot Texture Anchor

/// Describes a static texture pinned to an anchor slot of the skeleton. The image
/// is registered into the parent renderer's texture array once and rendered as a
/// quad at the anchor bone's world position, z-ordered with the anchor slot in the
/// skeleton's draw order. Shares the renderer's vertex/texture-index draw path with
/// embedded child skeletons.
public final class SpineSlotTextureAnchor {
    public let slotName: String
    public let textureIndex: Int
    public let width: Float
    public let height: Float
    public let offsetX: Float
    public let offsetY: Float

    public init(
        slotName: String,
        textureIndex: Int,
        width: Float,
        height: Float,
        offsetX: Float = 0,
        offsetY: Float = 0
    ) {
        self.slotName = slotName
        self.textureIndex = textureIndex
        self.width = width
        self.height = height
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

extension SpineController {
    public func slotIndex(_ slotName: String) -> Int32? {
        guard let slot = skeleton.findSlot(slotName) else {
            return nil
        }

        return slot.data.index
    }

    /// Pins a pre-registered texture (by parent-renderer texture index) to a slot.
    public func setSlotTextureAnchor(_ anchor: SpineSlotTextureAnchor) {
        slotTextureAnchors[anchor.slotName] = anchor
    }

    /// Loads an image from the bundle, registers it into the renderer's texture
    /// array, and pins it to the given slot. Mirrors `embedSpine(atlasFileName:...)`.
    ///
    /// - Parameters:
    ///   - imageName: Image name or path resolvable in `bundle`.
    ///   - slotName: Anchor slot in the skeleton.
    ///   - width/height: Quad size in skeleton units. Defaults to the image's point size.
    ///   - offsetX/offsetY: Additional offset from the anchor bone's world position.
    @MainActor
    @discardableResult
    public func setSlotTextureAnchor(
        imageNamed imageName: String,
        bundle: Bundle = .main,
        atSlotNamed slotName: String,
        width: Float? = nil,
        height: Float? = nil,
        offsetX: Float = 0,
        offsetY: Float = 0
    ) throws -> SpineSlotTextureAnchor {
        guard let renderer else {
            throw SpineExternalAttachmentError.rendererNotReady
        }

        guard skeleton.findSlot(slotName) != nil else {
            throw SpineExternalAttachmentError.slotNotFound(slotName)
        }

        let image = try Self.loadImage(imageName, bundle: bundle)
        let textureIndex = try renderer.registerTexture(image)

        let resolvedWidth = width ?? Float(image.size.width)
        let resolvedHeight = height ?? Float(image.size.height)

        let anchor = SpineSlotTextureAnchor(
            slotName: slotName,
            textureIndex: textureIndex,
            width: resolvedWidth,
            height: resolvedHeight,
            offsetX: offsetX,
            offsetY: offsetY
        )

        slotTextureAnchors[slotName] = anchor

        return anchor
    }

    public func removeSlotTextureAnchor(_ slotName: String) {
        slotTextureAnchors.removeValue(forKey: slotName)
    }
}
// MARK: Embed Child Spine

/// Describes a child skeleton embedded in-pass at an anchor slot of the parent
/// skeleton. The child is rendered inside the parent's render pass and is z-ordered
/// against the anchor slot in the parent's draw order.
public final class SpineSlotSpineAnchor {
    public let slotName: String
    public let childDrawable: SkeletonDrawableWrapper
    public let scale: Float
    public let offsetX: Float
    public let offsetY: Float

    /// Parent-renderer texture array indices for the child's atlas pages. Retained
    /// so the registered textures stay alive for the lifetime of the anchor.
    public internal(set) var pageTextureIndices: [Int]

    public init(
        slotName: String,
        childDrawable: SkeletonDrawableWrapper,
        scale: Float = 1,
        offsetX: Float = 0,
        offsetY: Float = 0,
        pageTextureIndices: [Int] = []
    ) {
        self.slotName = slotName
        self.childDrawable = childDrawable
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.pageTextureIndices = pageTextureIndices
    }
}

extension SpineController {
    /// Embeds a pre-loaded child skeleton at the given slot, rendering it in-pass.
    ///
    /// The child's atlas pages are registered into the parent renderer's texture
    /// array and the child's atlas regions are rebound to those indices, so the
    /// child's render commands carry valid texture indices for the parent renderer.
    ///
    /// - Returns: The embedded ``SpineSlotSpineAnchor``. Set an animation on
    ///   `anchor.childDrawable.animationState` to animate the child.
    @MainActor
    @discardableResult
    public func embedSpine(
        childDrawable: SkeletonDrawableWrapper,
        atSlotNamed slotName: String,
        scale: Float = 1,
        offsetX: Float = 0,
        offsetY: Float = 0
    ) throws -> SpineSlotSpineAnchor {
        guard let renderer else {
            throw SpineExternalAttachmentError.rendererNotReady
        }

        guard skeleton.findSlot(slotName) != nil else {
            throw SpineExternalAttachmentError.slotNotFound(slotName)
        }

        let pageImages = childDrawable.atlasPages
        let textureIndices = try renderer.registerTextures(pageImages)

        try Self.bindAtlasPagesAndRegions(
            atlas: childDrawable.atlas,
            textureIndices: textureIndices
        )

        let anchor = SpineSlotSpineAnchor(
            slotName: slotName,
            childDrawable: childDrawable,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY,
            pageTextureIndices: textureIndices
        )

        slotSpineAnchors[slotName] = anchor

        return anchor
    }

    /// Loads a child skeleton from bundled files and embeds it at the given slot.
    @MainActor
    @discardableResult
    public func embedSpine(
        atlasFileName: String,
        skeletonFileName: String,
        bundle: Bundle = .main,
        atSlotNamed slotName: String,
        scale: Float = 1,
        offsetX: Float = 0,
        offsetY: Float = 0
    ) async throws -> SpineSlotSpineAnchor {
        let atlasAndPages = try await Atlas.fromBundle(atlasFileName, bundle: bundle)
        let skeletonData = try await SkeletonData.fromBundle(
            atlas: atlasAndPages.0,
            skeletonFileName: skeletonFileName,
            bundle: bundle
        )

        let childDrawable = try SkeletonDrawableWrapper(
            atlas: atlasAndPages.0,
            atlasPages: atlasAndPages.1,
            skeletonData: skeletonData
        )

        return try embedSpine(
            childDrawable: childDrawable,
            atSlotNamed: slotName,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }

    /// Removes the embedded child skeleton anchored at the given slot.
    ///
    /// - Note: The child's textures registered into the parent renderer are not
    ///   reclaimed (the renderer only appends to its texture array), matching the
    ///   existing external-attachment behaviour. The child drawable is not disposed
    ///   here to avoid disposing while a frame referencing it may still be in flight.
    public func removeSpineAnchor(_ slotName: String) {
        slotSpineAnchors.removeValue(forKey: slotName)
    }
}

