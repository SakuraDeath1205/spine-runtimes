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
    }

    func isPlaying(_ spineRenderer: SpineRenderer) -> Bool {
        return isPlaying
    }

    func skeletonDrawable(_ spineRenderer: SpineRenderer) -> SkeletonDrawableWrapper {
        return drawable
    }

    func renderCommands(_ spineRenderer: SpineRenderer) -> [RenderCommand] {
        guard let drawable = drawable else { return [] }

        var commands = [RenderCommand]()
        var current = drawable.skeletonDrawable.render()
        while let cmd = current {
            commands.append(cmd)
            current = cmd.next
        }
        return commands
    }
}

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
