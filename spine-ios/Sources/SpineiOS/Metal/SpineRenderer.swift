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

import Foundation
import MetalKit
import SpineC
import SpineShadersStructs
import SpineSwift

protocol SpineRendererDelegate: AnyObject {
    func spineRendererWillUpdate(_ spineRenderer: SpineRenderer)
    func spineRenderer(_ spineRenderer: SpineRenderer, needsUpdate delta: TimeInterval)
    func spineRendererDidUpdate(_ spineRenderer: SpineRenderer)

    func spineRendererWillDraw(_ spineRenderer: SpineRenderer)
    func spineRendererDidDraw(_ spineRenderer: SpineRenderer)

    func spineRendererDidUpdate(_ spineRenderer: SpineRenderer, scaleX: CGFloat, scaleY: CGFloat, offsetX: CGFloat, offsetY: CGFloat, size: CGSize)
}

protocol SpineRendererDataSource: AnyObject {
    func isPlaying(_ spineRenderer: SpineRenderer) -> Bool
//     func renderCommands(_ spineRenderer: SpineRenderer) -> [RenderCommand]
    func renderItems(_ spineRenderer: SpineRenderer) -> [SpineRenderItem]
}

internal final class SpineRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private var textures: [MTLTexture]
    private let textureLoader: MTKTextureLoader
    private let commandQueue: MTLCommandQueue

    private var sizeInPoints: CGSize = .zero
    private var viewPortSize = vector_uint2(0, 0)
    private var transform = SpineTransform(
        translation: vector_float2(0, 0),
        scale: vector_float2(1, 1),
        offset: vector_float2(0, 0)
    )
    internal var lastDraw: CFTimeInterval = 0
    internal var waitUntilCompleted = false
    private var pipelineStatesByBlendMode = [Int: MTLRenderPipelineState]()

    private static let numberOfBuffers = 3
    private static let defaultBufferSize = 32 * 1024  // 32KB

    private var buffers = [MTLBuffer]()
    private let bufferingSemaphore = DispatchSemaphore(value: SpineRenderer.numberOfBuffers)
    private var currentBufferIndex: Int = 0

    weak var dataSource: SpineRendererDataSource?
    weak var delegate: SpineRendererDelegate?

    internal init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pixelFormat: MTLPixelFormat,
        atlasPages: [UIImage],
        pma: Bool
    ) throws {
        self.device = device
        self.commandQueue = commandQueue

        let bundle: Bundle
        #if SWIFT_PACKAGE  // SPM
            bundle = .module
        #else  // CocoaPods
            let bundleURL = Bundle(for: SpineRenderer.self).url(forResource: "SpineBundle", withExtension: "bundle")
            bundle = Bundle(url: bundleURL!)!
        #endif

        let defaultLibrary = try device.makeDefaultLibrary(bundle: bundle)
        let textureLoader = MTKTextureLoader(device: device)
        textures =
            try atlasPages
            .compactMap { $0.cgImage }
            .map {
                try textureLoader.newTexture(
                    cgImage: $0,
                    options: [
                        .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                        .SRGB: false,
                    ]
                )
            }

        let blendModes: [BlendMode] = [
            .normal,
            .additive,
            .multiply,
            .screen,
        ]
        for blendMode in blendModes {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = defaultLibrary.makeFunction(name: "vertexShader")
            descriptor.fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            descriptor.colorAttachments[0].apply(
                blendMode: blendMode,
                with: pma
            )
            pipelineStatesByBlendMode[Int(blendMode.rawValue)] = try device.makeRenderPipelineState(descriptor: descriptor)
        }

        self.textureLoader = textureLoader
        super.init()

        increaseBuffersSize(to: SpineRenderer.defaultBufferSize)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard let spineView = view as? SpineUIView else { return }

        sizeInPoints = CGSize(width: size.width / UIScreen.main.scale, height: size.height / UIScreen.main.scale)
        viewPortSize = vector_uint2(UInt32(size.width), UInt32(size.height))
        setTransform(
            bounds: spineView.computedBounds,
            mode: spineView.mode,
            alignment: spineView.alignment
        )
    }

    func draw(in view: MTKView) {
        guard dataSource?.isPlaying(self) ?? false else {
            lastDraw = CACurrentMediaTime()
            return
        }

        callNeedsUpdate()

        // Tripple Buffering
        // Source: https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html#//apple_ref/doc/uid/TP40016642-CH5-SW1
        bufferingSemaphore.wait()
        currentBufferIndex = (currentBufferIndex + 1) % SpineRenderer.numberOfBuffers

        guard let renderItems = dataSource?.renderItems(self),
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            bufferingSemaphore.signal()
            return
        }

        delegate?.spineRendererWillDraw(self)
        draw(renderItems: renderItems, renderEncoder: renderEncoder, in: view)
        delegate?.spineRendererDidDraw(self)

        renderEncoder.endEncoding()
        view.currentDrawable.flatMap {
            commandBuffer.present($0)
        }
        commandBuffer.addCompletedHandler { [bufferingSemaphore] _ in
            bufferingSemaphore.signal()
        }
        commandBuffer.commit()
        if waitUntilCompleted {
            commandBuffer.waitUntilCompleted()
        }
    }

private func draw(
    renderItems: [SpineRenderItem],
    renderEncoder: MTLRenderCommandEncoder,
    in view: MTKView
) {
    var preparedSpineVertices = [[SpineVertex]]()
    var requiredVerticesSize = 0

    for item in renderItems {
        switch item {
        case .spine(let command):
            let vertices = Array(command.getVertices())
            preparedSpineVertices.append(vertices)

            requiredVerticesSize = alignedMetalBufferOffset(requiredVerticesSize)
            requiredVerticesSize += MemoryLayout<SpineVertex>.stride * vertices.count

        case .externalTexture:
            break
        }
    }

    requiredVerticesSize = alignedMetalBufferOffset(requiredVerticesSize)

    var vertexBuffer: MTLBuffer?

    if requiredVerticesSize > 0 {
        var buffer = buffers[currentBufferIndex]

        if buffer.length < requiredVerticesSize {
            increaseBuffersSize(to: requiredVerticesSize)
            buffer = buffers[currentBufferIndex]
        }

        vertexBuffer = buffer
    }

    beginDraw(renderEncoder: renderEncoder)

    var vertexBufferOffset = 0
    var spineVertexIndex = 0

    for item in renderItems {
        switch item {
        case .spine(let command):
            guard let vertexBuffer else {
                continue
            }

            let vertices = preparedSpineVertices[spineVertexIndex]
            spineVertexIndex += 1

            vertexBufferOffset = alignedMetalBufferOffset(vertexBufferOffset)

            vertexBufferOffset = drawSpineCommand(
                command,
                vertices: vertices,
                vertexBuffer: vertexBuffer,
                vertexBufferOffset: vertexBufferOffset,
                renderEncoder: renderEncoder
            )

        case .externalTexture(let externalTexture):
//            drawExternalTexture(
//                externalTexture,
//                renderEncoder: renderEncoder
//            )
            print("exteranl texture")
        }
    }
}


    private func setTransform(bounds: CGRect, mode: SpineContentMode, alignment: SpineAlignment) {
        let x = -bounds.minX - bounds.width / 2.0
        let y = -bounds.minY - bounds.height / 2.0

        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0

        switch mode {
        case .fit:
            scaleX = min(sizeInPoints.width / bounds.width, sizeInPoints.height / bounds.height)
            scaleY = scaleX
        case .fill:
            scaleX = max(sizeInPoints.width / bounds.width, sizeInPoints.height / bounds.height)
            scaleY = scaleX
        }

        let offsetX = abs(sizeInPoints.width - bounds.width * scaleX) / 2 * alignment.x
        let offsetY = abs(sizeInPoints.height - bounds.height * scaleY) / 2 * alignment.y

        transform = SpineTransform(
            translation: vector_float2(Float(x), Float(y)),
            scale: vector_float2(Float(scaleX * UIScreen.main.scale), Float(scaleY * UIScreen.main.scale)),
            offset: vector_float2(Float(offsetX * UIScreen.main.scale), Float(offsetY * UIScreen.main.scale))
        )

        delegate?.spineRendererDidUpdate(
            self,
            scaleX: scaleX,
            scaleY: scaleY,
            offsetX: x + offsetX / scaleX,
            offsetY: y + offsetY / scaleY,
            size: sizeInPoints
        )
    }

    private func callNeedsUpdate() {
        if lastDraw == 0 {
            lastDraw = CACurrentMediaTime()
        }
        let delta = CACurrentMediaTime() - lastDraw
        delegate?.spineRendererWillUpdate(self)
        delegate?.spineRenderer(self, needsUpdate: delta)
        lastDraw = CACurrentMediaTime()
        delegate?.spineRendererDidUpdate(self)
    }

    // private func draw(
    //     renderCommands: [RenderCommand],
    //     renderEncoder: MTLRenderCommandEncoder,
    //     in view: MTKView
    // ) {
    //     let commandVertices = renderCommands.map { renderCommand in
    //         (renderCommand, Array(renderCommand.getVertices()))
    //     }

    //     var requiredVerticesSize = 0

    //     for pair in commandVertices {
    //         requiredVerticesSize = alignedMetalBufferOffset(requiredVerticesSize)
    //         requiredVerticesSize += MemoryLayout<SpineVertex>.stride * pair.1.count
    //     }

    //     requiredVerticesSize = alignedMetalBufferOffset(requiredVerticesSize)

    //     guard requiredVerticesSize > 0 else {
    //         return
    //     }

    //     var vertexBuffer = buffers[currentBufferIndex]

    //     if vertexBuffer.length < requiredVerticesSize {
    //         increaseBuffersSize(to: requiredVerticesSize)
    //         vertexBuffer = buffers[currentBufferIndex]
    //     }

    //     beginDraw(renderEncoder: renderEncoder)

    //     var vertexBufferOffset = 0

    //     for pair in commandVertices {
    //         vertexBufferOffset = alignedMetalBufferOffset(vertexBufferOffset)

    //         vertexBufferOffset = drawSpineCommand(
    //             pair.0,
    //             vertices: pair.1,
    //             vertexBuffer: vertexBuffer,
    //             vertexBufferOffset: vertexBufferOffset,
    //             renderEncoder: renderEncoder
    //         )
    //     }
    // }

    private func beginDraw(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setViewport(
            MTLViewport(
                originX: 0.0,
                originY: 0.0,
                width: Double(viewPortSize.x),
                height: Double(viewPortSize.y),
                znear: 0.0,
                zfar: 1.0
            )
        )

        renderEncoder.setVertexBytes(
            &transform,
            length: MemoryLayout.size(ofValue: transform),
            index: Int(SpineVertexInputIndexTransform.rawValue)
        )

        renderEncoder.setVertexBytes(
            &viewPortSize,
            length: MemoryLayout.size(ofValue: viewPortSize),
            index: Int(SpineVertexInputIndexViewportSize.rawValue)
        )
    }

    private func alignedMetalBufferOffset(_ value: Int) -> Int {
        let alignment = 256
        return (value + alignment - 1) & ~(alignment - 1)
    }

    @discardableResult
    private func drawSpineCommand(
        _ renderCommand: RenderCommand,
        vertices: [SpineVertex],
        vertexBuffer: MTLBuffer,
        vertexBufferOffset: Int,
        renderEncoder: MTLRenderCommandEncoder
    ) -> Int {
        let alignedOffset = alignedMetalBufferOffset(vertexBufferOffset)
        let verticesSize = MemoryLayout<SpineVertex>.stride * vertices.count

        guard verticesSize > 0 else {
            return alignedOffset
        }

        vertices.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                return
            }

            let destination = vertexBuffer.contents().advanced(by: alignedOffset)
            memcpy(destination, baseAddress, verticesSize)
        }

        guard let pipelineState = getPipelineState(blendMode: renderCommand.blendMode) else {
            return alignedMetalBufferOffset(alignedOffset + verticesSize)
        }

        renderEncoder.setRenderPipelineState(pipelineState)

        renderEncoder.setVertexBuffer(
            vertexBuffer,
            offset: alignedOffset,
            index: Int(SpineVertexInputIndexVertices.rawValue)
        )

        let textureIndex = Int(bitPattern: renderCommand.texture)

        if textures.indices.contains(textureIndex) {
            renderEncoder.setFragmentTexture(
                textures[textureIndex],
                index: Int(SpineTextureIndexBaseColor.rawValue)
            )
        }

        renderEncoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: vertices.count
        )

        return alignedMetalBufferOffset(alignedOffset + verticesSize)
    }

    private func getPipelineState(blendMode: BlendMode) -> MTLRenderPipelineState? {
        pipelineStatesByBlendMode[Int(blendMode.rawValue)]
    }

    private func increaseBuffersSize(to size: Int) {
        buffers = (0..<SpineRenderer.numberOfBuffers).map { _ in
            device.makeBuffer(length: size, options: .storageModeShared)!
        }
    }

    // 把新的 UIImage 注册进 renderer 的 texture 数组，并返回 textureIndex
    internal func registerTexture(_ image: UIImage) throws -> Int {
        guard let cgImage = image.cgImage else {
            throw SpineExternalAttachmentError.invalidImage
        }

        let texture = try textureLoader.newTexture(
            cgImage: cgImage,
            options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .SRGB: NSNumber(value: false)
            ]
        )

        textures.append(texture)
        return textures.count - 1
    }

    // 注册atlas多图
    internal func registerTextures(_ images: [UIImage]) throws -> [Int] {
    try images.map { try registerTexture($0) }
}
}

extension BlendMode {
    fileprivate func sourceRGBBlendFactor(premultipliedAlpha: Bool) -> MTLBlendFactor {
        switch self {
        case .normal:
            return premultipliedAlpha ? .one : .sourceAlpha
        case .additive:
            // additvie only needs sourceAlpha multiply if it is not pma
            return premultipliedAlpha ? .one : .sourceAlpha
        case .multiply:
            return .destinationColor
        case .screen:
            return .one
        }
    }

    fileprivate var sourceAlphaBlendFactor: MTLBlendFactor {
        // pma and non-pma has no-relation ship with alpha blending
        switch self {
        case .normal:
            return .one
        case .additive:
            return .one
        case .multiply:
            return .oneMinusSourceAlpha
        case .screen:
            return .oneMinusSourceColor
        }
    }

    fileprivate var destinationRGBBlendFactor: MTLBlendFactor {
        switch self {
        case .normal:
            return .oneMinusSourceAlpha
        case .additive:
            return .one
        case .multiply:
            return .oneMinusSourceAlpha
        case .screen:
            return .oneMinusSourceColor
        }
    }

    fileprivate var destinationAlphaBlendFactor: MTLBlendFactor {
        switch self {
        case .normal:
            return .oneMinusSourceAlpha
        case .additive:
            return .one
        case .multiply:
            return .oneMinusSourceAlpha
        case .screen:
            return .oneMinusSourceColor
        }
    }
}

extension MTLRenderPipelineColorAttachmentDescriptor {

    fileprivate func apply(blendMode: BlendMode, with premultipliedAlpha: Bool) {
        isBlendingEnabled = true
        sourceRGBBlendFactor = blendMode.sourceRGBBlendFactor(premultipliedAlpha: premultipliedAlpha)
        sourceAlphaBlendFactor = blendMode.sourceAlphaBlendFactor
        destinationRGBBlendFactor = blendMode.destinationRGBBlendFactor
        destinationAlphaBlendFactor = blendMode.destinationAlphaBlendFactor
    }
}
