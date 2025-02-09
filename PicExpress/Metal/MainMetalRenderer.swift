//
//  MainMetalRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import simd

/// Common uniform struct for polygons, triangles, etc.
struct TransformUniforms {
    var transform: float4x4
    var polygonColor: SIMD4<Float> = .init(1, 0, 0, 1)
}

final class MainMetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?

    // Sub-renderers
    private let triangleRenderer: TriangleRenderer
    private let polygonRenderer: PolygonRenderer
    let pointsRenderer: PointsRenderer?

    var previewColor: SIMD4<Float> = .init(1, 1, 1, 1)

    // For transform
    private var uniformBuffer: MTLBuffer?
    private var uniforms = TransformUniforms(transform: matrix_identity_float4x4)

    private var zoom: Float = 1.0
    private var pan: SIMD2<Float> = .zero

    // Do we show the triangle test ?
    private var showTriangleFlag: Bool

    private let texWidth: Int
    private let texHeight: Int

    // The texture for pixel fill
    var fillTexture: MTLTexture?
    var cpuBuffer: [UInt8]?

    init(mtkView: MTKView,
         showTriangle: Bool,
         width: Int,
         height: Int)
    {
        self.showTriangleFlag = showTriangle
        self.texWidth = width
        self.texHeight = height

        guard let dev = mtkView.device else {
            fatalError("No MTLDevice found for this MTKView.")
        }
        self.device = dev

        let library = device.makeDefaultLibrary()

        // Sub-renderers
        self.triangleRenderer = TriangleRenderer(device: device, library: library)
        self.polygonRenderer = PolygonRenderer(device: device, library: library)
        self.pointsRenderer = PointsRenderer(device: device, library: library)

        super.init()

        buildResources()
    }

    private func buildResources() {
        commandQueue = device.makeCommandQueue()

        // Create uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<TransformUniforms>.size,
                                          options: [])

        // Create fillTexture with doc size
        let desc = MTLTextureDescriptor()
        desc.pixelFormat = .rgba8Unorm
        desc.width = texWidth
        desc.height = texHeight
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .managed

        if let t = device.makeTexture(descriptor: desc) {
            fillTexture = t
            cpuBuffer = [UInt8](repeating: 0, count: texWidth * texHeight * 4)

            if var cbuf = cpuBuffer {
                // Fill with black or any color
                for i in 0 ..< (texWidth * texHeight) {
                    let idx = i * 4
                    cbuf[idx+0] = 0 // R
                    cbuf[idx+1] = 0 // G
                    cbuf[idx+2] = 0 // B
                    cbuf[idx+3] = 255 // A
                }
                // Upload to GPU
                t.replace(region: MTLRegionMake2D(0, 0, texWidth, texHeight),
                          mipmapLevel: 0,
                          withBytes: &cbuf,
                          bytesPerRow: texWidth * 4)

                cpuBuffer = cbuf
            }
        }
    }

    // MARK: - Public

    func showTriangle(_ flag: Bool) {
        showTriangleFlag = flag
    }

    func setZoomAndPan(zoom: CGFloat, panOffset: CGSize) {
        self.zoom = Float(zoom)
        pan.x = Float(panOffset.width)
        pan.y = Float(panOffset.height)
    }

    func clearPolygons() {
        polygonRenderer.clearPolygons()
    }

    func addPolygon(points: [ECTPoint], color: SIMD4<Float>) {
        polygonRenderer.addPolygon(points: points, color: color)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // We can handle resizing if we want, but we keep our texture size fixed.
    }

    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmdQ = commandQueue,
              let cmdBuff = cmdQ.makeCommandBuffer()
        else { return }

        updateUniforms()

        let encoder = cmdBuff.makeRenderCommandEncoder(descriptor: rpd)!

        // optional triangle
        if showTriangleFlag {
            triangleRenderer.draw(
                encoder: encoder,
                uniformBuffer: uniformBuffer
            )
        }

        // polygons
        polygonRenderer.draw(
            encoder: encoder,
            uniformBuffer: uniformBuffer
        )

        // points
        pointsRenderer?.draw(
            encoder: encoder,
            uniformBuffer: uniformBuffer
        )

        encoder.endEncoding()
        cmdBuff.present(drawable)
        cmdBuff.commit()
    }

    private func updateUniforms() {
        // build transform from zoom/pan
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

        uniforms.transform = translationMatrix * scaleMatrix
        uniforms.polygonColor = previewColor

        if let ub = uniformBuffer {
            memcpy(ub.contents(), &uniforms, MemoryLayout<TransformUniforms>.size)
        }
    }
}
