//
//  PolygonRenderer.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import simd

/// Each polygon we store for rendering
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

    /// Access to the global appState to check fill mode, polygon algorithm, etc.
    private weak var appState: AppState?

    private var clipWindow: [ECTPoint] = []

    init(device: MTLDevice, library: MTLLibrary?, appState: AppState?) {
        self.device = device
        self.appState = appState
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

    // MARK: - Public API

    /// Optionnel: un setter pour la fenêtre de clipping
    func setClipWindow(_ points: [ECTPoint]) {
        clipWindow = points
        print("PolygonRenderer: clipWindow updated with \(points.count) points.")
    }

    /// Adds a polygon. color => the polygon's unique color
    @MainActor func addPolygon(points: [ECTPoint], color: SIMD4<Float>) {
        guard let appState = appState else { return }

        // 1) Selon l'algo choisi
        var finalPoints = points

        switch appState.selectedPolygonAlgorithm {
        case .earClipping:
            // pas de clipping => triangulation direct
            break

        case .cyrusBeck:
            finalPoints = clipPolygonWithCyrusBeck(finalPoints)

        case .sutherlandHodgman:
            finalPoints = clipPolygonWithSutherlandHodgman(finalPoints)
        }

        // 2) Triangulate the final polygon with ear clipping so we can draw triangles
        let polygon = ECTPolygon(vertices: finalPoints)
        let earClip = EarClippingTriangulation()
        let triangles = earClip.getEarClipTriangles(polygon: polygon)

        // 3) Build geometry
        var uniqueMap = [ECTPoint: UInt16]()
        var polyVertices: [PolygonVertex] = []
        polyVertices.reserveCapacity(triangles.count * 3)

        var currentIndex: UInt16 = 0
        func addVertexIfNeeded(_ p: ECTPoint) -> UInt16 {
            if let idx = uniqueMap[p] {
                return idx
            }
            uniqueMap[p] = currentIndex
            let vx = PolygonVertex(
                position: SIMD2<Float>(Float(p.x), Float(p.y)),
                uv: SIMD2<Float>(Float(p.x + 0.5), Float(p.y + 0.5)),
                color: color
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

        guard !polyVertices.isEmpty, !indices.isEmpty else {
            return
        }

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

    /// Clear all polygons
    func clearPolygons() {
        polygons.removeAll()
    }

    @MainActor func draw(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer?) {
        guard let pipeline = pipelineState,
              let appState = appState else { return }

        // Fill or line?
        if appState.fillPolygonBackground {
            encoder.setTriangleFillMode(.fill)
        } else {
            encoder.setTriangleFillMode(.lines)
        }

        for poly in polygons {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(poly.vertexBuffer, offset: 0, index: 0)

            if let ub = uniformBuffer {
                encoder.setVertexBuffer(ub, offset: 0, index: 1)
            }

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: poly.indexCount,
                indexType: .uint16,
                indexBuffer: poly.indexBuffer,
                indexBufferOffset: 0
            )
        }
    }

    @MainActor private func clipPolygonWithCyrusBeck(_ points: [ECTPoint]) -> [ECTPoint] {
        // If there is a locally defined clipWindow, we use it
        if clipWindow.count >= 3 {
            return cyrusBeckClip(subjectPolygon: points, clipWindow: clipWindow)
        }
        // else, we can see if the appState has lassoPoints
        if let appState = appState, appState.lassoPoints.count >= 3 {
            return cyrusBeckClip(subjectPolygon: points, clipWindow: appState.lassoPoints)
        }
        // if nothing => no clipping
        return points
    }

    @MainActor private func clipPolygonWithSutherlandHodgman(_ points: [ECTPoint]) -> [ECTPoint] {
        if clipWindow.count >= 3 {
            return sutherlandHodgmanClip(subjectPolygon: points, clipWindow: clipWindow)
        }
        if let appState = appState, appState.lassoPoints.count >= 3 {
            return sutherlandHodgmanClip(subjectPolygon: points, clipWindow: appState.lassoPoints)
        }
        return points
    }
}
