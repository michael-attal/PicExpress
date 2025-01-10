//
//  TriangleRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit

final class TriangleRenderer {
    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState?
    
    init(device: MTLDevice, library: MTLLibrary?) {
        self.device = device
        buildPipeline(library: library)
    }
    
    private func buildPipeline(library: MTLLibrary?) {
        guard let library = library else { return }
        
        let vertexFunction   = library.makeFunction(name: "vs_triangle_gradient")
        let fragmentFunction = library.makeFunction(name: "fs_triangle_gradient")
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragmentFunction
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("TriangleRenderer: failed to create pipeline state:", error)
        }
    }
    
    func draw(
        encoder: MTLRenderCommandEncoder,
        uniformBuffer: MTLBuffer?
    ) {
        guard let pipeline = pipelineState else { return }
        
        encoder.setRenderPipelineState(pipeline)
        
        if let ub = uniformBuffer {
            encoder.setVertexBuffer(ub, offset: 0, index: 1)
        }
        
        // Hard coded triangle
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
