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
    /// We added a zoomFactor so that other shaders (e.g. PointsPreview) can
    /// adapt their rendering (like pointSize) depending on the current zoom.
    var zoomFactor: Float = 1.0
    var _padding: SIMD2<Float> = .zero
}

/// This class is the main renderer for your project. It handles:
/// - A single big mesh (MeshRenderer) for all polygons
/// - CPU-based fill (seed, scanline, LCA) in a texture, using a buffer
/// - Zoom/pan transform
public final class MainMetalRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private var commandQueue: MTLCommandQueue?

    // The big mesh renderer
    let meshRenderer: MeshRenderer

    // Optionally keep your points preview
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
    private var fillTexture: MTLTexture?
    private var cpuBuffer: [UInt8] = []

    // Zoom/pan
    private var zoom: Float = 1.0
    private var pan: SIMD2<Float> = .zero

    /// Expose the final transform so we can invert it in the Coordinator
    /// to place points accurately under the mouse even when zoomed/panned.
    public private(set) var currentTransform: float4x4 = matrix_identity_float4x4

    // This color is for preview or uniform
    var previewColor: SIMD4<Float> = .init(1, 1, 1, 1)

    // MARK: - Storing the last mesh for export

    private var _lastVertices: [PolygonVertex] = []
    private var _lastIndices: [UInt16] = []

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

        self.commandQueue = dev.makeCommandQueue()
        buildResources()
    }

    // MARK: - Build resources

    private func buildResources() {
        // Create the uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<TransformUniforms>.size,
                                          options: [])
        uniforms.docWidth = Float(texWidth)
        uniforms.docHeight = Float(texHeight)

        // Create fillTexture => doc size
        let desc = MTLTextureDescriptor()
        desc.pixelFormat = .rgba8Unorm
        desc.width = texWidth
        desc.height = texHeight
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .managed
        fillTexture = device.makeTexture(descriptor: desc)

        // CPU buffer for fill
        cpuBuffer = [UInt8](repeating: 0, count: texWidth * texHeight * 4)
        for i in 0 ..< (texWidth * texHeight) {
            let idx = i * 4
            cpuBuffer[idx+0] = 0 // R
            cpuBuffer[idx+1] = 0 // G
            cpuBuffer[idx+2] = 0 // B
            cpuBuffer[idx+3] = 255 // A
        }
        updateFillTextureCPU(cpuBuffer)
    }

    // MARK: - Big mesh usage

    /// Build the big mesh from user polygons. Optionally do a clipping with a given algorithm.
    /// Then we ear-clip everything, gather triangles, create a single vertex/index buffer.
    @MainActor
    public func buildGlobalMesh(polygons: [[SIMD2<Float>]],
                                clippingAlgorithm: AvailableClippingAlgorithm?,
                                clipWindow: [SIMD2<Float>],
                                color: SIMD4<Float>)
    {
        var finalTriangles: [ECTTriangle] = []

        for poly in polygons {
            guard poly.count >= 3 else { continue }

            // 1) Do clipping if needed
            let clippedPoly: [SIMD2<Float>]
            switch clippingAlgorithm {
            case .cyrusBeck:
                clippedPoly = ClippingAlgorithms.cyrusBeckClip(subjectPolygon: poly, clipWindow: clipWindow)
            case .sutherlandHodgman:
                clippedPoly = ClippingAlgorithms.sutherlandHodgmanClip(subjectPolygon: poly, clipWindow: clipWindow)
            case .none:
                clippedPoly = poly
            }

            // 2) Ear clipping => produce triangles
            let earClip = EarClippingTriangulation()
            let ectPoly = ECTPolygon(vertices: clippedPoly.map {
                ECTPoint(x: Double($0.x), y: Double($0.y))
            })
            let triList = earClip.getEarClipTriangles(polygon: ectPoly)
            finalTriangles.append(contentsOf: triList)
        }

        // Build the final big mesh
        var vertices: [PolygonVertex] = []
        var indices: [UInt16] = []
        var currentIndex: UInt16 = 0

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

            vertices.append(
                PolygonVertex(
                    position: A,
                    uv: .zero,
                    color: color
                )
            )
            vertices.append(
                PolygonVertex(
                    position: B,
                    uv: .zero,
                    color: color
                )
            )
            vertices.append(
                PolygonVertex(
                    position: C,
                    uv: .zero,
                    color: color
                )
            )
        }

        // Update the meshRenderer
        meshRenderer.updateMesh(vertices: vertices, indices: indices)

        // Store these arrays for potential export
        _lastVertices = vertices
        _lastIndices = indices
    }

    // MARK: - Exporting the current mesh

    /// Returns the last built mesh (vertices + indices) if it exists.
    public func exportCurrentMesh() -> ([PolygonVertex], [UInt16])? {
        guard !_lastVertices.isEmpty, !_lastIndices.isEmpty else {
            return nil
        }
        return (_lastVertices, _lastIndices)
    }

    // MARK: - CPU fill usage

    /// Calls one of the 4 fill algorithms (seed recursive, seed stack, scanline, LCA) on cpuBuffer,
    /// then re-uploads to fillTexture.
    /// - polygon is used for LCA
    /// - seed is used for the germ-based approaches
    public func applyFillAlgorithm(
        algo: AvailableFillAlgorithm,
        polygon: [SIMD2<Float>],
        seed: (Int, Int)?,
        fillRule: FillRule
    ) {
        let fillColor: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255) // Example: red

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
            // fill the entire polygon
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
    }

    /// Re-upload CPU buffer to fillTexture
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

    /// Called by the Coordinator to set the zoom and panOffset.
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

        // Draw the big mesh
        meshRenderer.draw(encoder, uniformBuffer: uniformBuffer)

        // Optionally draw preview points
        pointsRenderer?.draw(encoder: encoder, uniformBuffer: uniformBuffer)

        encoder.endEncoding()
        cmdBuff.present(drawable)
        cmdBuff.commit()
    }

    /// This function updates `uniforms.transform` with translation * scale,
    /// sets `uniforms.zoomFactor`, and copies the data to the GPU buffer.
    private func updateUniforms() {
        // Zoom factor
        let s = zoom

        // Build scale matrix
        let scaleMatrix = float4x4(
            simd_float4(s, 0, 0, 0),
            simd_float4(0, s, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )

        // Convert panOffset to a [-1..1] range shift
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
        uniforms.zoomFactor = s // We store the actual zoom in the uniform

        // Keep a copy so the Coordinator can invert it
        currentTransform = finalTransform

        if let ub = uniformBuffer {
            memcpy(ub.contents(), &uniforms, MemoryLayout<TransformUniforms>.size)
        }
    }
}

public extension MainMetalRenderer {
    /// Update the points preview in the PointsPreviewRenderer.
    /// We pass an array of ECTPoint in pixel coords (doc coords),
    /// then the GPU will convert them to clip space in the vs_points_preview shader.
    func updatePreviewPoints(_ ectPoints: [ECTPoint]) {
        pointsRenderer?.updatePreviewPoints(ectPoints)
    }
}
