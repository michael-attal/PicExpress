//
//  MeshRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 12/02/2025.
//

import MetalKit
import simd

/// This struct is used as the single big mesh vertex
public struct PolygonVertex: Codable {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>

    /// We store up to 4 polygon IDs.
    /// If a vertex belongs to multiple polygons, we can store them here.
    /// Set them to -1 if unused.
    var polygonIDs: simd_int4
}

/// A single big mesh (vertexBuffer + indexBuffer).
/// We do one single drawIndexedPrimitives(...) in draw().
final class MeshRenderer {
    public var mainRenderer: MainMetalRenderer?
    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState?

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    init(device: MTLDevice, library: MTLLibrary?) {
        self.device = device
        buildPipeline(library: library)
    }

    private func buildPipeline(library: MTLLibrary?) {
        guard let library = library else { return }

        let vertexFunc = library.makeFunction(name: "vs_mesh")
        let fragmentFunc = library.makeFunction(name: "fs_mesh_textured")

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragmentFunc
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.rasterSampleCount = 4 // Avoid pixelated shapes.

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("MeshRenderer: failed to create pipeline =>", error)
        }
    }

    /// Replaces the entire mesh with new vertices + indices
    func updateMesh(vertices: [PolygonVertex], indices: [UInt16]) {
        guard !vertices.isEmpty, !indices.isEmpty else {
            vertexBuffer = nil
            indexBuffer = nil
            indexCount = 0
            return
        }
        let vSize = vertices.count * MemoryLayout<PolygonVertex>.stride
        let iSize = indices.count * MemoryLayout<UInt16>.stride

        guard let vb = device.makeBuffer(bytes: vertices, length: vSize, options: []),
              let ib = device.makeBuffer(bytes: indices, length: iSize, options: [])
        else {
            return
        }
        vertexBuffer = vb
        indexBuffer = ib
        indexCount = indices.count

        mainRenderer?.lastVertices = vertices
        mainRenderer?.lastIndices = indices
    }

    @MainActor func draw(_ encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer?) {
        guard let pipeline = pipelineState,
              let vb = vertexBuffer,
              let ib = indexBuffer,
              indexCount > 0
        else {
            return
        }

        let useFillTexture = mainRenderer?.appState?.shouldFillMeshWithBackground ?? true

        encoder.setTriangleFillMode(useFillTexture ? .fill : .lines)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vb, offset: 0, index: 0)
        if let ub = uniformBuffer {
            encoder.setVertexBuffer(ub, offset: 0, index: 1)
        }

        var textureFlag = useFillTexture
        encoder.setFragmentBytes(&textureFlag, length: MemoryLayout<Bool>.size, index: 0)

        if let mainRenderer = mainRenderer,
           let tex = mainRenderer.fillTexture
        {
            encoder.setFragmentTexture(tex, index: 0)
        }

        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: indexCount,
                                      indexType: .uint16,
                                      indexBuffer: ib,
                                      indexBufferOffset: 0)
    }
}
