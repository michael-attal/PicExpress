//
//  MainMetalRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import simd

/// Common uniform struct for transforms in the vertex shader.
struct TransformUniforms {
    var transform: simd_float4x4
    var polygonColor: SIMD4<Float>
    var docWidth: Float
    var docHeight: Float
    var zoomFactor: Float = 1.0
    var _padding: SIMD2<Float> = .zero
}

/// This class is the main renderer for the project. It handles:
/// - A single big mesh (MeshRenderer) for all polygons
/// - CPU-based fill (seed, scanline, LCA) in a texture, using a buffer
/// - A fill texture that displays the rendering
/// - Zoom/pan transform
public final class MainMetalRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private var commandQueue: MTLCommandQueue?

    // The big mesh renderer
    let meshRenderer: MeshRenderer

    // Optionally keep our points preview
    let pointsRenderer: PointsPreviewRenderer?

    private var uniformBuffer: MTLBuffer?

    private var uniforms = TransformUniforms(
        transform: matrix_identity_float4x4,
        polygonColor: SIMD4<Float>(1, 1, 1, 1),
        docWidth: 512,
        docHeight: 512
    )

    let texWidth: Int
    let texHeight: Int

    // For CPU-based fill usage
    public var fillTexture: MTLTexture?
    public var cpuBuffer: [UInt8] = []

    // Zoom/pan
    private var zoom: Float = 1.0
    private var pan: SIMD2<Float> = .zero

    // Expose the final transform so we can invert it in the Coordinator
    public private(set) var currentTransform: float4x4 = matrix_identity_float4x4

    // This color is for preview or uniform
    var previewColor: SIMD4<Float> = .init(1, 1, 1, 1)

    // MARK: - Storing the last mesh for export

    var lastVertices: [PolygonVertex] = []
    var lastIndices: [UInt16] = []

    weak var appState: AppState?

    // MARK: - Init

    public init(mtkView: MTKView, width: Int, height: Int) {
        self.texWidth = width
        self.texHeight = height

        guard let dev = mtkView.device else {
            fatalError("No MTLDevice found for this MTKView.")
        }
        self.device = dev

        let library = device.makeDefaultLibrary()
        self.meshRenderer = MeshRenderer(device: dev, library: library)
        self.pointsRenderer = PointsPreviewRenderer(device: dev, library: library)

        super.init()

        meshRenderer.mainRenderer = self
        self.commandQueue = dev.makeCommandQueue()
        buildResources()
    }

    // MARK: - Build resources

    private func buildResources() {
        uniformBuffer = device.makeBuffer(length: MemoryLayout<TransformUniforms>.size,
                                          options: [])
        uniforms.docWidth = Float(texWidth)
        uniforms.docHeight = Float(texHeight)

        let desc = MTLTextureDescriptor()
        desc.pixelFormat = .rgba8Unorm
        desc.width = texWidth
        desc.height = texHeight
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .managed
        fillTexture = device.makeTexture(descriptor: desc)

        cpuBuffer = [UInt8](repeating: 0, count: texWidth * texHeight * 4)
        for i in 0 ..< (texWidth * texHeight) {
            let idx = i * 4
            cpuBuffer[idx+0] = 0
            cpuBuffer[idx+1] = 0
            cpuBuffer[idx+2] = 0
            cpuBuffer[idx+3] = 255
        }
        updateFillTextureCPU(cpuBuffer)
    }

    // MARK: - Big mesh usage

    @MainActor
    public func buildGlobalMesh(polygons: [[SIMD2<Float>]],
                                clippingAlgorithm: AvailableClippingAlgorithm?,
                                clipWindow: [SIMD2<Float>],
                                color: SIMD4<Float>)
    {
        var finalTriangles: [ECTTriangle] = []

        for poly in polygons {
            guard poly.count >= 3 else { continue }
            let clippedPoly: [SIMD2<Float>]
            switch clippingAlgorithm {
            case .cyrusBeck:
                // TODO: clippedPoly = ClippingAlgorithms.cyrusBeckClip(...)
                // Fallback
                clippedPoly = ClippingAlgorithms.sutherlandHodgmanClip(subjectPolygon: poly, clipWindow: clipWindow)
            case .sutherlandHodgman:
                clippedPoly = ClippingAlgorithms.sutherlandHodgmanClip(subjectPolygon: poly, clipWindow: clipWindow)
            case .none:
                clippedPoly = poly
            }

            let earClip = EarClippingTriangulation()
            let ectPoly = ECTPolygon(vertices: clippedPoly.map {
                ECTPoint(x: Double($0.x), y: Double($0.y))
            })
            let triList = earClip.getEarClipTriangles(polygon: ectPoly)
            finalTriangles.append(contentsOf: triList)
        }

        var vertices: [PolygonVertex] = []
        var indices: [UInt16] = []
        var currentIndex: UInt16 = 0

        // Suppose we assign the same polygonID=0 for all in this example:
        // (In a real scenario, we might pass different IDs per polygon).
        let polygonID: Int32 = 0

        for tri in finalTriangles {
            let iA = currentIndex
            let iB = currentIndex+1
            let iC = currentIndex+2
            currentIndex += 3

            indices.append(iA)
            indices.append(iB)
            indices.append(iC)

            let A = SIMD2<Float>(Float(tri.a.x), Float(tri.a.y))
            let B = SIMD2<Float>(Float(tri.b.x), Float(tri.b.y))
            let C = SIMD2<Float>(Float(tri.c.x), Float(tri.c.y))

            let defaultIDs = simd_int4(polygonID, -1, -1, -1)

            vertices.append(
                PolygonVertex(
                    position: A,
                    uv: .zero,
                    color: color,
                    polygonIDs: defaultIDs
                )
            )
            vertices.append(
                PolygonVertex(
                    position: B,
                    uv: .zero,
                    color: color,
                    polygonIDs: defaultIDs
                )
            )
            vertices.append(
                PolygonVertex(
                    position: C,
                    uv: .zero,
                    color: color,
                    polygonIDs: defaultIDs
                )
            )
        }

        meshRenderer.updateMesh(vertices: vertices, indices: indices)

        lastVertices = vertices
        lastIndices = indices
    }

    // MARK: - Exporting the current mesh

    public func exportCurrentMesh() -> ([PolygonVertex], [UInt16])? {
        guard !lastVertices.isEmpty, !lastIndices.isEmpty else {
            return nil
        }
        return (lastVertices, lastIndices)
    }

    // MARK: - CPU fill usage

    @MainActor public func applyFillAlgorithm(
        algo: AvailableFillAlgorithm,
        polygon: [SIMD2<Float>],
        seed: (Int, Int)?,
        fillColor: (UInt8, UInt8, UInt8, UInt8),
        fillRule: FillRule
    ) {
        switch algo {
        case .seedRecursive:
            if let s = seed {
                let target = FillAlgorithms.getPixelColor(cpuBuffer, texWidth, texHeight, s.0, s.1)
                FillAlgorithms.seedFillRecursive(&cpuBuffer, texWidth, texHeight,
                                                 s.0, s.1,
                                                 target, fillColor)
            }
        case .seedStack:
            if let s = seed {
                let target = FillAlgorithms.getPixelColor(cpuBuffer, texWidth, texHeight, s.0, s.1)
                FillAlgorithms.seedFillStack(&cpuBuffer, texWidth, texHeight,
                                             s.0, s.1,
                                             target, fillColor)
            }
        case .scanline:
            if let s = seed {
                let target = FillAlgorithms.getPixelColor(cpuBuffer, texWidth, texHeight, s.0, s.1)
                FillAlgorithms.scanlineFill(&cpuBuffer, texWidth, texHeight,
                                            s.0, s.1,
                                            target, fillColor)
            }
        case .lca:
            FillAlgorithms.fillPolygonLCA(
                polygon: polygon,
                pixels: &cpuBuffer,
                width: texWidth,
                height: texHeight,
                fillColor: fillColor,
                fillRule: fillRule
            )
        }

        updateFillTextureCPU(cpuBuffer)
        if let doc = appState?.selectedDocument {
            doc.saveFillTexture(cpuBuffer, width: texWidth, height: texHeight)
            print("Texture saved.")
        } else {
            print("No document selected to save fill texture.")
        }
    }

    public func updateFillTextureCPU(_ buf: [UInt8]) {
        guard let tex = fillTexture else { return }
        tex.replace(
            region: MTLRegionMake2D(0, 0, texWidth, texHeight),
            mipmapLevel: 0,
            withBytes: buf,
            bytesPerRow: texWidth * 4
        )
    }

    // MARK: - Zoom & Pan

    public func setZoomAndPan(zoom: CGFloat, panOffset: CGSize) {
        self.zoom = Float(zoom)
        pan.x = Float(panOffset.width)
        pan.y = Float(panOffset.height)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // not used
    }

    public func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmdBuff = commandQueue?.makeCommandBuffer()
        else { return }

        updateUniforms()

        let encoder = cmdBuff.makeRenderCommandEncoder(descriptor: rpd)!

        meshRenderer.draw(encoder, uniformBuffer: uniformBuffer)
        pointsRenderer?.draw(encoder: encoder, uniformBuffer: uniformBuffer)

        encoder.endEncoding()
        cmdBuff.present(drawable)
        cmdBuff.commit()
    }

    private func updateUniforms() {
        let s = zoom
        let scaleMatrix = float4x4(
            simd_float4(s, 0, 0, 0),
            simd_float4(0, s, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )

        let tx = pan.x * 2.0
        let ty = -pan.y * 2.0
        let translationMatrix = float4x4(
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(tx, ty, 0, 1)
        )

        let finalTransform = translationMatrix * scaleMatrix

        uniforms.transform = finalTransform
        uniforms.polygonColor = previewColor
        uniforms.zoomFactor = s
        currentTransform = finalTransform

        if let ub = uniformBuffer {
            memcpy(ub.contents(), &uniforms, MemoryLayout<TransformUniforms>.size)
        }
    }

    // MARK: - pointInTriangle helper

    /// Return true if p is inside triangle ABC (2D).
    public func pointInTriangle(
        p: SIMD2<Float>,
        a: SIMD2<Float>,
        b: SIMD2<Float>,
        c: SIMD2<Float>
    ) -> Bool {
        let v0 = c - a
        let v1 = b - a
        let v2 = p - a

        let dot00 = simd_dot(v0, v0)
        let dot01 = simd_dot(v0, v1)
        let dot02 = simd_dot(v0, v2)
        let dot11 = simd_dot(v1, v1)
        let dot12 = simd_dot(v1, v2)

        let invDenom = 1.0 / (dot00 * dot11 - dot01 * dot01)
        let u = (dot11 * dot02 - dot01 * dot12) * invDenom
        let v = (dot00 * dot12 - dot01 * dot02) * invDenom

        return (u >= 0) && (v >= 0) && (u+v <= 1)
    }
}

public extension MainMetalRenderer {
    func updatePreviewPoints(_ ectPoints: [ECTPoint]) {
        pointsRenderer?.updatePreviewPoints(ectPoints)
    }

    func reloadCPUBuf(_ newBuf: [UInt8]) {
        if newBuf.count == cpuBuffer.count {
            cpuBuffer = newBuf
            updateFillTextureCPU(cpuBuffer)
            print("Reloaded CPU buffer from doc.")
        } else {
            print("Error: mismatch in buffer size => cannot reload")
        }
    }
}
