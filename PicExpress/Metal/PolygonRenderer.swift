//
//  PolygonRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import simd

/// Each polygon we store for rendering.
/// If 'usesTexture' is true, we sample from 'texture' in fs_polygon_textured.
/// Otherwise, we use the color from the vertex in fs_polygon.
struct PolygonVertex {
    var position: SIMD2<Float> // in pixel coords
    var uv: SIMD2<Float>
    var color: SIMD4<Float>
}

struct PolygonData {
    var vertexBuffer: MTLBuffer
    var indexBuffer: MTLBuffer
    var indexCount: Int

    var texture: MTLTexture? // if we are using a texture
    var usesTexture: Bool // if true => sample from texture
}

/// This renderer is responsible for drawing multiple polygons.
/// Some polygons might be solid-color, some might be textured.
final class PolygonRenderer {
    private let device: MTLDevice

    /// Two pipeline states: one for color-only polygons, one for textured polygons
    private var pipelineStateColor: MTLRenderPipelineState?
    private var pipelineStateTexture: MTLRenderPipelineState?

    /// A reference to the global appState if needed
    private weak var appState: AppState?

    /// The local storage of polygons that we will draw.
    public var polygons: [PolygonData] = []

    /// We can keep a clipWindow if we do polygon clipping in the GPU or else
    private var clipWindow: [ECTPoint] = []

    init(device: MTLDevice, library: MTLLibrary?, appState: AppState?) {
        self.device = device
        self.appState = appState
        buildPipeline(library: library)
    }

    /// Build two pipeline states:
    /// - pipelineStateColor => vs_polygon + fs_polygon
    /// - pipelineStateTexture => vs_polygon + fs_polygon_textured
    private func buildPipeline(library: MTLLibrary?) {
        guard let library = library else { return }

        // 1) Pipeline for color
        let vertexFunc = library.makeFunction(name: "vs_polygon")
        let fragmentFunc = library.makeFunction(name: "fs_polygon")

        let descColor = MTLRenderPipelineDescriptor()
        descColor.vertexFunction = vertexFunc
        descColor.fragmentFunction = fragmentFunc
        descColor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineStateColor = try device.makeRenderPipelineState(descriptor: descColor)
        } catch {
            print("PolygonRenderer: failed to create pipelineStateColor =>", error)
        }

        // 2) Pipeline for texture
        let vertexFuncTex = library.makeFunction(name: "vs_polygon")
        let fragmentFuncTex = library.makeFunction(name: "fs_polygon_textured")

        let descTex = MTLRenderPipelineDescriptor()
        descTex.vertexFunction = vertexFuncTex
        descTex.fragmentFunction = fragmentFuncTex
        descTex.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineStateTexture = try device.makeRenderPipelineState(descriptor: descTex)
        } catch {
            print("PolygonRenderer: failed to create pipelineStateTexture =>", error)
        }
    }

    /// If we need a "clip window" for dynamic clipping
    func setClipWindow(_ points: [ECTPoint]) {
        clipWindow = points
        print("PolygonRenderer: clipWindow updated with \(points.count) points.")
    }

    /// Adds a new polygon into our internal list, optionally skipping the built-in ear clipping if the polygon is already triangulated.
    /// - Parameters:
    ///   - points: The polygon's vertex coordinates in our document space (pixel coords).
    ///   - color: The polygon color (SIMD4<Float> = RGBA).
    ///   - alreadyTriangulated: If `true`, we assume `points` is a flat list of triangles (3 vertices per triangle). No ear clipping is applied.
    @MainActor
    func addPolygon(points: [ECTPoint],
                    color: SIMD4<Float>,
                    alreadyTriangulated: Bool = false)
    {
        guard let appState = appState else { return }

        // 1) Optionally apply polygon clipping with the current "clipWindow" (if not already triangulated)
        var finalPoints = points
        switch appState.selectedPolygonAlgorithm {
        case .cyrusBeck:
            if !clipWindow.isEmpty, !alreadyTriangulated {
                finalPoints = cyrusBeckClip(subjectPolygon: finalPoints, clipWindow: clipWindow)
            }
        case .sutherlandHodgman:
            if !clipWindow.isEmpty, !alreadyTriangulated {
                finalPoints = sutherlandHodgmanClip(subjectPolygon: finalPoints, clipWindow: clipWindow)
            }
        }

        // 2) If `alreadyTriangulated == true`, we skip the ear clipping,
        //    assuming that `points` are already provided as triangles (groups of 3).
        if alreadyTriangulated {
            let vertexCount = finalPoints.count
            // We expect multiple of 3
            if vertexCount < 3 { return }

            // Build an index buffer: for example, [0,1,2, 3,4,5, 6,7,8, ...]
            var indices: [UInt16] = []
            indices.reserveCapacity(vertexCount)
            for i in stride(from: 0, to: vertexCount, by: 3) {
                indices.append(UInt16(i))
                indices.append(UInt16(i + 1))
                indices.append(UInt16(i + 2))
            }

            // Convert ECTPoints into PolygonVertex (position + uv + color)
            var polyVertices: [PolygonVertex] = []
            polyVertices.reserveCapacity(vertexCount)

            let docW = Float(appState.selectedDocument?.width ?? 512)
            let docH = Float(appState.selectedDocument?.height ?? 512)

            for p in finalPoints {
                let u = Float(p.x) / docW
                let v = Float(p.y) / docH
                polyVertices.append(
                    PolygonVertex(
                        position: SIMD2<Float>(Float(p.x), Float(p.y)),
                        uv: SIMD2<Float>(u, v),
                        color: color
                    )
                )
            }

            guard let vb = device.makeBuffer(bytes: polyVertices,
                                             length: polyVertices.count * MemoryLayout<PolygonVertex>.stride,
                                             options: []),
                let ib = device.makeBuffer(bytes: indices,
                                           length: indices.count * MemoryLayout<UInt16>.stride,
                                           options: [])
            else {
                return
            }

            let polyData = PolygonData(
                vertexBuffer: vb,
                indexBuffer: ib,
                indexCount: indices.count,
                texture: nil,
                usesTexture: false
            )

            polygons.append(polyData)
            return
        }

        // 3) If not triangulated, we do a normal ear clipping
        let polygon = ECTPolygon(vertices: finalPoints)
        let earClip = EarClippingTriangulation()
        let triangles = earClip.getEarClipTriangles(polygon: polygon)
        if triangles.isEmpty { return }

        // Build a unique vertex list + index list
        // Each triangle => (a, b, c)
        var polyVertices: [PolygonVertex] = []
        var uniqueMap = [ECTPoint: UInt16]()
        var currentIndex: UInt16 = 0
        var indices: [UInt16] = []

        let docW = Float(appState.selectedDocument?.width ?? 512)
        let docH = Float(appState.selectedDocument?.height ?? 512)

        func addVertexIfNeeded(_ pt: ECTPoint) -> UInt16 {
            if let idx = uniqueMap[pt] {
                return idx
            }
            uniqueMap[pt] = currentIndex

            let u = Float(pt.x) / docW
            let v = Float(pt.y) / docH
            polyVertices.append(
                PolygonVertex(
                    position: SIMD2<Float>(Float(pt.x), Float(pt.y)),
                    uv: SIMD2<Float>(u, v),
                    color: color
                )
            )
            let thisIdx = currentIndex
            currentIndex += 1
            return thisIdx
        }

        for tri in triangles {
            let iA = addVertexIfNeeded(tri.a)
            let iB = addVertexIfNeeded(tri.b)
            let iC = addVertexIfNeeded(tri.c)
            indices.append(iA)
            indices.append(iB)
            indices.append(iC)
        }

        guard !polyVertices.isEmpty, !indices.isEmpty else { return }

        guard let vb = device.makeBuffer(bytes: polyVertices,
                                         length: polyVertices.count * MemoryLayout<PolygonVertex>.stride,
                                         options: []),
            let ib = device.makeBuffer(bytes: indices,
                                       length: indices.count * MemoryLayout<UInt16>.stride,
                                       options: [])
        else {
            return
        }

        let newPoly = PolygonData(
            vertexBuffer: vb,
            indexBuffer: ib,
            indexCount: indices.count,
            texture: nil,
            usesTexture: false
        )
        polygons.append(newPoly)
    }

    /// Clears our polygon list
    func clearPolygons() {
        polygons.removeAll()
    }

    /// The main draw call: for each polygon, we pick the pipeline (texture or color),
    /// then set the buffers, then draw.
    @MainActor
    func draw(_ encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer?) {
        guard let appState = appState else { return }

        for poly in polygons {
            // fill or lines => we read from appState
            let fillMode: MTLTriangleFillMode = appState.fillPolygonBackground ? .fill : .lines
            encoder.setTriangleFillMode(fillMode)

            // If poly.usesTexture => pipelineStateTexture
            if poly.usesTexture, let pipelineTex = pipelineStateTexture {
                encoder.setRenderPipelineState(pipelineTex)
                if let tex = poly.texture {
                    encoder.setFragmentTexture(tex, index: 0)
                }
            } else {
                // color pipeline
                if let pipelineCol = pipelineStateColor {
                    encoder.setRenderPipelineState(pipelineCol)
                }
            }

            // set the vertex buffer
            encoder.setVertexBuffer(poly.vertexBuffer, offset: 0, index: 0)
            // uniform
            if let ub = uniformBuffer {
                encoder.setVertexBuffer(ub, offset: 0, index: 1)
            }

            // draw the triangles
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: poly.indexCount,
                indexType: .uint16,
                indexBuffer: poly.indexBuffer,
                indexBufferOffset: 0
            )
        }
    }

    // MARK: - Clipping utils (cyrusBeckClip, sutherlandHodgmanClip, etc.)

    func cyrusBeckClip(subjectPolygon: [ECTPoint], clipWindow: [ECTPoint]) -> [ECTPoint] {
        return cyrusBeckClip(subjectPolygon: subjectPolygon, clipWindow: clipWindow)
    }

    func sutherlandHodgmanClip(subjectPolygon: [ECTPoint], clipWindow: [ECTPoint]) -> [ECTPoint] {
        return sutherlandHodgmanClip(subjectPolygon: subjectPolygon, clipWindow: clipWindow)
    }
}
