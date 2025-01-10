//
//  PolygonRenderer.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import simd

struct PolygonVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var color: SIMD4<Float>
}

struct PolygonData {
    var vertexBuffer: MTLBuffer
    var indexBuffer: MTLBuffer
    var indexCount: Int
}

final class PolygonRenderer {
    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState?
    
    // Multiple polygons can be stored (each with its own geometry)
    private(set) var polygons: [PolygonData] = []
    
    init(device: MTLDevice, library: MTLLibrary?) {
        self.device = device
        buildPipeline(library: library)
    }
    
    private func buildPipeline(library: MTLLibrary?) {
        guard let library = library else { return }
        
        let vertexFunc = library.makeFunction(name: "vs_polygon")
        let fragmentFunc = library.makeFunction(name: "fs_polygon")
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragmentFunc
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("PolygonRenderer: failed to create pipeline state:", error)
        }
    }
    
    /// Adds a polygon. color' => the polygon's unique color
    func addPolygon(points: [ECTPoint], color: SIMD4<Float>) {
        // 1) Triangulate with ear clipping
        let polygon = ECTPolygon(vertices: points)
        let earClip = EarClippingTriangulation()
        let triangles = earClip.getEarClipTriangles(polygon: polygon)
        
        // 2) Builds a list of vertices/indexes
        var uniqueMap = [ECTPoint: UInt16]()
        var polyVertices: [PolygonVertex] = []
        var currentIndex: UInt16 = 0
        
        func addVertexIfNeeded(_ p: ECTPoint) -> UInt16 {
            if let idx = uniqueMap[p] { return idx }
            uniqueMap[p] = currentIndex
            let vx = PolygonVertex(
                position: SIMD2<Float>(Float(p.x), Float(p.y)),
                uv: SIMD2<Float>(Float(p.x + 0.5), Float(p.y + 0.5)),
                color: color // All vertices receive the same color
            )
            polyVertices.append(vx)
            let c = currentIndex
            currentIndex += 1
            return c
        }
        
        var indices: [UInt16] = []
        for tri in triangles {
            let iA = addVertexIfNeeded(tri.a)
            let iB = addVertexIfNeeded(tri.b)
            let iC = addVertexIfNeeded(tri.c)
            indices.append(contentsOf: [iA, iB, iC])
        }
        
        // 3) MTLBuffer creation
        let vb = device.makeBuffer(
            bytes: polyVertices,
            length: polyVertices.count * MemoryLayout<PolygonVertex>.stride,
            options: []
        )!
        let ib = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt16>.stride,
            options: []
        )!
        
        let polyData = PolygonData(
            vertexBuffer: vb,
            indexBuffer: ib,
            indexCount: indices.count
        )
        polygons.append(polyData)
    }
    
    func clearPolygons() {
        polygons.removeAll()
    }
    
    /// Draws all polygons
    func draw(encoder: MTLRenderCommandEncoder,
              uniformBuffer: MTLBuffer?)
    {
        guard let pipeline = pipelineState else { return }
        
        for poly in polygons {
            encoder.setRenderPipelineState(pipeline)
            
            // buffer(0) -> geometry
            encoder.setVertexBuffer(poly.vertexBuffer, offset: 0, index: 0)
            
            // buffer(1) -> TransformUniforms
            if let ub = uniformBuffer {
                encoder.setVertexBuffer(ub, offset: 0, index: 1)
            }
            
            // draw
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: poly.indexCount,
                indexType: .uint16,
                indexBuffer: poly.indexBuffer,
                indexBufferOffset: 0
            )
        }
    }
}
