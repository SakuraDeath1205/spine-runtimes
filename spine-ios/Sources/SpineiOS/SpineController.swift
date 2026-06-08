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
    let attachment: RegionAttachment
    let region: TextureRegion
    let image: UIImage
    let atlas: Atlas?

    init(
        attachment: RegionAttachment,
        region: TextureRegion,
        image: UIImage,
        atlas: Atlas?
    ) {
        self.attachment = attachment
        self.region = region
        self.image = image
        self.atlas = atlas
    }
}

public enum SpineExternalAttachmentError: Error {
    case rendererNotReady
    case imageNotFound(String)
    case invalidImage
    case slotNotFound(String)
    case attachmentNotFound(slot: String, attachment: String?)
    case templateIsNotRegionAttachment(String)
    case atlasRegionNotFound(String)
    case atlasPageNotFound
}

extension SpineController {
    @MainActor
    public func replaceRegionAttachment(
        slotName: String,
        pngFileName: String,
        atlasFileName: String? = nil,
        regionName: String? = nil,
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

        let templateAttachment: Attachment?

        if let templateAttachmentName {
            templateAttachment = skeleton.getAttachment(slotName, templateAttachmentName)
        } else {
            templateAttachment = slot.appliedPose.attachment ?? slot.pose.attachment
        }

        guard let templateAttachment else {
            throw SpineExternalAttachmentError.attachmentNotFound(
                slot: slotName,
                attachment: templateAttachmentName
            )
        }

        guard let template = templateAttachment as? RegionAttachment else {
            throw SpineExternalAttachmentError.templateIsNotRegionAttachment(templateAttachment.name)
        }

        let copied = template.copyAttachment() as! RegionAttachment

        let image = try Self.loadImage(pngFileName, bundle: bundle)
        let textureIndex = try renderer.registerTexture(image)

        let runtimeRegion: TextureRegion
        var ownedAtlas: Atlas?

        if let atlasFileName {
            let atlasAndPages = try await Atlas.fromBundle(atlasFileName, bundle: bundle)
            let externalAtlas = atlasAndPages.0
            ownedAtlas = externalAtlas

            let lookupName = regionName ?? (template.path.isEmpty ? template.name : template.path)

            guard let atlasRegion = externalAtlas.findRegion(lookupName) else {
                throw SpineExternalAttachmentError.atlasRegionNotFound(lookupName)
            }

            atlasRegion.setRendererObjectTextureIndex(textureIndex)

            if let page = atlasRegion.page {
                page.setTextureIndex(textureIndex)
            } else {
                throw SpineExternalAttachmentError.atlasPageNotFound
            }

            runtimeRegion = atlasRegion
            copied.path = lookupName
        } else {
            guard let cgImage = image.cgImage else {
                throw SpineExternalAttachmentError.invalidImage
            }

            let region = TextureRegion()
            region.u = 0
            region.v = 0
            region.u2 = 1
            region.v2 = 1
            region.regionWidth = Int32(cgImage.width)
            region.regionHeight = Int32(cgImage.height)
            region.setRendererObjectTextureIndex(textureIndex)

            runtimeRegion = region
            copied.path = regionName ?? pngFileName

            if !keepTemplateSize {
                copied.width = Float(cgImage.width)
                copied.height = Float(cgImage.height)
            }
        }

        copied.sequence.setSingleRegionAndUpdate(runtimeRegion, attachment: copied)

        slot.pose.attachment = copied
        slot.appliedPose.attachment = copied

        externalAttachmentStore["\(slotName)::\(templateAttachmentName ?? "__current__")"] =
            ExternalAttachmentHandle(
                attachment: copied,
                region: runtimeRegion,
                image: image,
                atlas: ownedAtlas
            )
    }

    private static func loadImage(_ nameOrPath: String, bundle: Bundle) throws -> UIImage {
        if let image = UIImage(named: nameOrPath, in: bundle, compatibleWith: nil) {
            return image
        }

        let url = URL(fileURLWithPath: nameOrPath)
        if let image = UIImage(contentsOfFile: url.path) {
            return image
        }

        throw SpineExternalAttachmentError.imageNotFound(nameOrPath)
    }

}