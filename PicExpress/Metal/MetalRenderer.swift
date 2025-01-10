//
//  MetalRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import simd

struct TransformUniforms {
    var transform: float4x4 = matrix_identity_float4x4
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?

    // Uniform buffer for transform (zoom + pan)
    private var uniformBuffer: MTLBuffer?

    // We'll keep track of zoom & pan inside the renderer
    private var zoom: Float = 1.0
    private var pan: SIMD2<Float> = .init(0, 0)

    // Our TransformUniforms
    private var uniforms = TransformUniforms()

    init(mtkView: MTKView) {
        // 1. Device
        guard let device = mtkView.device else {
            fatalError("MTKView has no MTLDevice.")
        }
        self.device = device
        super.init()

        // 2. Create resources
        buildResources(mtkView: mtkView)
    }

    // We'll expose this so the Coordinator can call it when zoom/pan changes
    func setZoomAndPan(zoom: CGFloat, panOffset: CGSize) {
        self.zoom = Float(zoom)
        pan = SIMD2<Float>(Float(panOffset.width), Float(panOffset.height))
    }

    private func buildResources(mtkView: MTKView) {
        // 2bis. Command queue
        commandQueue = device.makeCommandQueue()

        // 3. Load the Metal library
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create Metal library.")
        }

        // 4. Create the pipeline
        let vertexFunction = library.makeFunction(name: "vs_triangle_gradient")
        let fragmentFunction = library.makeFunction(name: "fs_triangle_gradient")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create pipeline state: \(error)")
        }

        // 5. Create a uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<TransformUniforms>.size, options: [])
    }

    // Compute the matrix each frame
    private func updateUniforms(drawableSize: CGSize) {
        // Build a scaling matrix
        let s = zoom
        let scaleMatrix = float4x4(
            simd_float4(s, 0, 0, 0),
            simd_float4(0, s, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )

        // Build a translation matrix
        // Pan scaled by 2.0 in clip space
        let tx = pan.x * 2.0
        let ty = -pan.y * 2.0

        let translationMatrix = float4x4(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(tx, ty, 0, 1)
        )

        // Combine them: transform = translation * scale
        uniforms.transform = translationMatrix * scaleMatrix

        if let buffer = uniformBuffer {
            memcpy(buffer.contents(), &uniforms, MemoryLayout<TransformUniforms>.size)
        }
    }

    // MARK: - MTKViewDelegate

    /// Called if view size changes
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // handle resizing if needed
    }

    /// Called every frame to draw
    func draw(in view: MTKView) {
        guard
            let passDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandQueue = commandQueue,
            let pipelineState = pipelineState,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            return
        }

        // Update the uniform buffer
        updateUniforms(drawableSize: view.drawableSize)

        // Set pipeline & uniforms
        encoder.setRenderPipelineState(pipelineState)

        if let buffer = uniformBuffer {
            encoder.setVertexBuffer(buffer, offset: 0, index: 1)
        }

        // Draw the triangle (3 vertices)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // End & commit
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
