//
//  MetalRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    
    init(mtkView: MTKView) {
        guard let device = mtkView.device else {
            fatalError("MTKView has no MTLDevice.")
        }
        self.device = device
        super.init()
        
        // Creates CommandQueue and pipeline
        buildResources(mtkView: mtkView)
    }
    
    private func buildResources(mtkView: MTKView) {
        // 1. Creation of a command queue
        commandQueue = device.makeCommandQueue()
        
        // 2. Retrieving the Metal library (which includes all metal files)
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create Metal library.")
        }
        
        // TODO: Replace by whatever we are working on, for the moment lets put a simple triangle
        // 3. Functions (vertex & fragment) corresponding to shaders
        let vertexFunction = library.makeFunction(name: "vs_triangle_gradient")
        let fragmentFunction = library.makeFunction(name: "fs_triangle_gradient")
        
        // 4. Pipeline descriptor creation
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        
        // 5. Pipeline state creation
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create pipeline state: \(error)")
        }
    }
    
    // MARK: - MTKViewDelegate
    
    /// Called if view size changes
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // TODO: Handle view resize here
    }
    
    /// Called every frame to draw
    func draw(in view: MTKView) {
        guard
            let pipelineState = pipelineState,
            let commandQueue = commandQueue,
            let passDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            return
        }
        
        // 1. Command buffer creation
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        // 2. Render command encoder creation
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
        encoder.setRenderPipelineState(pipelineState)
        
        // 3. Draw a triangle (3 vertices). No vertex buffer is passed,
        // because vertex_id is used in vertex shader (implicit index).
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        // 4. End & commit
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
