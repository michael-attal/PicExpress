//
//  PointsRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 08/02/2025.
//

import MetalKit
import simd

struct PointVertex {
    var position: SIMD2<Float>
}

/// This renderer draws a set of points for preview
final class PointsRenderer {
    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState?
    
    private var vertexBuffer: MTLBuffer?
    private var pointCount: Int = 0
    
    init(device: MTLDevice, library: MTLLibrary?) {
        self.device = device
        buildPipeline(library: library)
    }
    
    private func buildPipeline(library: MTLLibrary?) {
        guard let library = library else { return }

        let vertexFunc = library.makeFunction(name: "vs_points_preview")
        let fragmentFunc = library.makeFunction(name: "fs_points_preview")

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragmentFunc
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<PointVertex>.stride
        
        desc.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("PointsRenderer: failed to create pipeline state:", error)
        }
    }
    
    /// Update the array of points to display
    func updatePreviewPoints(_ points: [ECTPoint]) {
        if points.isEmpty {
            vertexBuffer = nil
            pointCount = 0
            return
        }
        
        var vertices: [PointVertex] = []
        vertices.reserveCapacity(points.count)
        for p in points {
            vertices.append(PointVertex(position: SIMD2<Float>(Float(p.x), Float(p.y))))
        }
        pointCount = vertices.count
        
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<PointVertex>.stride,
            options: []
        )
    }
    
    func draw(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer?) {
        guard let pipeline = pipelineState,
              let vb = vertexBuffer,
              pointCount > 0
        else {
            return
        }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vb, offset: 0, index: 0)
        
        // transform is at index=1
        if let ub = uniformBuffer {
            encoder.setVertexBuffer(ub, offset: 0, index: 1)
        }
        
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)
    }
}
