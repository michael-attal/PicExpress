//
//  GPUFillRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

// BONUS: Fill on gpu manually

import MetalKit
import simd

/// A renderer that draws ONE GPU fill polygon (pointInPolygon in a fragment shader).
/// - Build a “vs_fillPolygon”/“fs_fillPolygon” pipeline (see GPUFill.metal).
/// - Create a quad occupying the entire screen in clip space [-1..1]^2.
/// - Convert this quad into a coords bounding box, and test for membership.
final class GPUFillRenderer {
    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState?

    private var polygonBuffer: MTLBuffer?
    private var vertexBuffer: MTLBuffer?

    private var vertexCount: Int = 0

    struct FillPolygonVertexIn {
        var position: SIMD2<Float>
    }

    // Must correspond exactly to “PolygonData” on the .metal side
    struct PolygonData {
        var count: UInt32
        var pts: [SIMD2<Float>] // max 128
        var bbMin: SIMD2<Float>
        var bbMax: SIMD2<Float>
        var fillColor: SIMD4<Float>
    }

    init(device: MTLDevice, library: MTLLibrary?) {
        self.device = device
        buildPipeline(library: library)
        buildQuadVertexBuffer()
    }

    private func buildPipeline(library: MTLLibrary?) {
        guard let library = library else { return }

        let vs = library.makeFunction(name: "vs_fillPolygon")
        let fs = library.makeFunction(name: "fs_fillPolygon")

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("GPUFillRenderer: cannot create pipeline =>", error)
        }
    }

    /// We build a VBO with 4 vertices occupying the entire clip space [-1..1]^2
    /// DrawPrimitives(type: .triangleStrip, vertexCount: 4)
    private func buildQuadVertexBuffer() {
        let verts: [FillPolygonVertexIn] = [
            FillPolygonVertexIn(position: SIMD2<Float>(-1, -1)), // bottom-left
            FillPolygonVertexIn(position: SIMD2<Float>(-1, 1)), // top-left
            FillPolygonVertexIn(position: SIMD2<Float>(1, -1)), // bottom-right
            FillPolygonVertexIn(position: SIMD2<Float>(1, 1)) // top-right
        ]
        let bufSize = MemoryLayout<FillPolygonVertexIn>.stride * verts.count
        vertexBuffer = device.makeBuffer(bytes: verts, length: bufSize, options: [])
        vertexCount = verts.count
    }

    /// Prepare the “PolygonData” to be sent as buffer(1)
    /// polygon: list of vertices in float2
    /// fillColor: RGBA color (float4)
    func setPolygon(polygon: [SIMD2<Float>], fillColor: SIMD4<Float>) {
        guard polygon.count >= 3 else {
            polygonBuffer = nil
            return
        }
        // bounding box
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude

        for p in polygon {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }

        var data = PolygonData(
            count: UInt32(polygon.count),
            pts: Array(repeating: SIMD2<Float>(0, 0), count: 128),
            bbMin: SIMD2<Float>(minX, minY),
            bbMax: SIMD2<Float>(maxX, maxY),
            fillColor: fillColor
        )
        // copy vertices
        for i in 0 ..< polygon.count {
            data.pts[i] = polygon[i]
        }

        let bufSize = MemoryLayout<PolygonData>.size
        let buf = device.makeBuffer(length: bufSize, options: [])!
        memcpy(buf.contents(), &data, bufSize)
        polygonBuffer = buf
    }

    /// Draws in the current renderEncoder (color in colorAttachments[0])
    func draw(encoder: MTLRenderCommandEncoder) {
        guard let pipeline = pipelineState,
              let vb = vertexBuffer,
              let pb = polygonBuffer
        else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        // buffer(0) => quad
        encoder.setVertexBuffer(vb, offset: 0, index: 0)
        // buffer(1) => polygon data
        encoder.setVertexBuffer(pb, offset: 0, index: 1)
        encoder.setFragmentBuffer(pb, offset: 0, index: 1)

        // We draw a TRiangleStrip => 2 triangles => 4 vertices
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
    }
}
