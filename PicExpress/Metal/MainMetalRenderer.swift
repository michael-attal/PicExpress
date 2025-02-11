//
//  MainMetalRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import simd

/// Common uniform struct for polygons, points, etc.
/// Must match exactly the Metal side in size (96 bytes)
struct TransformUniforms {
    var transform: simd_float4x4 // 64
    var polygonColor: SIMD4<Float> // 16 => 80
    var docWidth: Float // 4  => 84
    var docHeight: Float // 4  => 88
    // Force alignment to 16 => we add 8 bytes so total=96
    var _padding: SIMD2<Float> = .zero
}

public final class MainMetalRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private var commandQueue: MTLCommandQueue?

    // Sub-renderers
    let triangleRenderer: TriangleRenderer
    let polygonRenderer: PolygonRenderer
    let pointsRenderer: PointsPreviewRenderer?
    let gpuFillRenderer: GPUFillRenderer

    var previewColor: SIMD4<Float> = .init(1, 1, 1, 1)

    // For transform
    private var uniformBuffer: MTLBuffer?
    private var uniforms = TransformUniforms(
        transform: matrix_identity_float4x4,
        polygonColor: SIMD4<Float>(1, 1, 1, 1),
        docWidth: 512,
        docHeight: 512
    )

    private var zoom: Float = 1.0
    private var pan: SIMD2<Float> = .zero

    // Do we show the triangle test ?
    private var showTriangleFlag: Bool

    let texWidth: Int
    let texHeight: Int

    // The texture for pixel fill
    var fillTexture: MTLTexture?
    var cpuBuffer: [UInt8]?

    // We keep a reference to appState to know fill modes, etc.
    private weak var appState: AppState?

    init(mtkView: MTKView,
         showTriangle: Bool,
         width: Int,
         height: Int,
         appState: AppState?)
    {
        self.showTriangleFlag = showTriangle
        self.texWidth = width
        self.texHeight = height
        self.appState = appState

        guard let dev = mtkView.device else {
            fatalError("No MTLDevice found for this MTKView.")
        }
        self.device = dev

        let library = device.makeDefaultLibrary()

        // Sub-renderers
        self.triangleRenderer = TriangleRenderer(device: device, library: library)
        self.polygonRenderer = PolygonRenderer(device: device, library: library, appState: appState)
        self.pointsRenderer = PointsPreviewRenderer(device: device, library: library)
        self.gpuFillRenderer = GPUFillRenderer(device: device, library: library)

        super.init()

        buildResources()
    }

    private func buildResources() {
        commandQueue = device.makeCommandQueue()

        // Create the uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<TransformUniforms>.size,
                                          options: [])
        // Set docWidth/docHeight
        uniforms.docWidth = Float(texWidth)
        uniforms.docHeight = Float(texHeight)

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
                // Fill with black
                for i in 0 ..< (texWidth * texHeight) {
                    let idx = i * 4
                    cbuf[idx+0] = 0 // R
                    cbuf[idx+1] = 0 // G
                    cbuf[idx+2] = 0 // B
                    cbuf[idx+3] = 255 // A
                }
                t.replace(region: MTLRegionMake2D(0, 0, texWidth, texHeight),
                          mipmapLevel: 0,
                          withBytes: &cbuf,
                          bytesPerRow: texWidth * 4)
                cpuBuffer = cbuf
            }
        }
    }

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

    func setClipWindow(_ points: [ECTPoint]) {
        polygonRenderer.setClipWindow(points)
    }

    @MainActor
    func addPolygon(points: [ECTPoint], color: SIMD4<Float>, alreadyTriangulated: Bool = false) {
        polygonRenderer.addPolygon(points: points, color: color, alreadyTriangulated: alreadyTriangulated)
    }

    // MARK: - GPU fill => Bonus function

    /// “Fills” the polygon (e.g. the one containing (sx,sy))
    /// by drawing in fillTexture via a render pass offscreen,
    /// so that the texture is modified.
    ///
    /// polygonPoints = the polygon's [SIMD2<Float>] list
    /// color = the RGBA color
    ///
    /// Can be called from fillTexturePixelByPixel(...) if fillAlgo==.gpuFragment
    @MainActor
    func fillPolygonOnGPU(polygonPoints: [SIMD2<Float>], color: SIMD4<Float>) {
        guard let cmdQ = commandQueue,
              let cmdBuff = cmdQ.makeCommandBuffer(),
              let fillTex = fillTexture
        else {
            print("No commandQueue or fillTexture => can't GPU fill.")
            return
        }

        // We configure the pipeline
        gpuFillRenderer.setPolygon(polygon: polygonPoints, fillColor: color)

        // We want to write in fillTex
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = fillTex
        rpd.colorAttachments[0].loadAction = .load // we want to keep what was already there
        rpd.colorAttachments[0].storeAction = .store // store the result
        // => if we want to clear : .clear + define clearColor

        if let encoder = cmdBuff.makeRenderCommandEncoder(descriptor: rpd) {
            gpuFillRenderer.draw(encoder: encoder)
            encoder.endEncoding()
        }

        cmdBuff.commit()
        cmdBuff.waitUntilCompleted()

        // => fillTexture is updated
        // Reload cpuBuffer
        if var cbuf = cpuBuffer {
            fillTex.getBytes(&cbuf,
                             bytesPerRow: fillTex.width * 4,
                             from: MTLRegionMake2D(0, 0, fillTex.width, fillTex.height),
                             mipmapLevel: 0)
            cpuBuffer = cbuf
        }
    }

    @MainActor
    func updateFillTextureCPU(buffer: [UInt8]) {
        guard let fillTex = fillTexture else { return }
        fillTex.replace(
            region: MTLRegionMake2D(0, 0, texWidth, texHeight),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: texWidth * 4
        )
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // not used
    }

    public func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmdQ = commandQueue,
              let cmdBuff = cmdQ.makeCommandBuffer() else { return }

        updateUniforms()

        let encoder = cmdBuff.makeRenderCommandEncoder(descriptor: rpd)!

        if showTriangleFlag {
            triangleRenderer.draw(
                encoder: encoder,
                uniformBuffer: uniformBuffer
            )
        }

        polygonRenderer.draw(
            encoder,
            uniformBuffer: uniformBuffer
        )

        pointsRenderer?.draw(
            encoder: encoder,
            uniformBuffer: uniformBuffer
        )

        encoder.endEncoding()
        cmdBuff.present(drawable)
        cmdBuff.commit()
    }

    private func updateUniforms() {
        let s = zoom
        // Scale matrix for zoom
        let scaleMatrix = float4x4(
            simd_float4(s, 0, 0, 0),
            simd_float4(0, s, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )
        // Translate matrix for pan
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
