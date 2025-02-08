//
//  MainMetalRenderer.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import simd

/// Common shader struct (Polygon.metal/TriangleGradientColor.metal/...)
struct TransformUniforms {
    var transform: float4x4
    var polygonColor: SIMD4<Float> = .init(1, 0, 0, 1)
}

final class MainMetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    
    // Sub-renderers, we can add more if needed
    private let triangleRenderer: TriangleRenderer
    private let polygonRenderer: PolygonRenderer
    let pointsRenderer: PointsRenderer? // Add a pointsRenderer for preview when placing point on "Polygone par clic" mode
    var previewColor: SIMD4<Float> = .init(1, 1, 0, 1) // color of preview points
    
    // Buffers
    private var uniformBuffer: MTLBuffer?
    private var uniforms = TransformUniforms(transform: matrix_identity_float4x4)
    
    // Zoom/pan
    private var zoom: Float = 1.0
    private var pan: SIMD2<Float> = .zero
    
    // For testing: Do we show the triangle from Triangle Renderer or not
    private var showTriangle: Bool
    
    // MARK: - Init

    init(mtkView: MTKView, showTriangle: Bool) {
        self.showTriangle = showTriangle
        
        guard let device = mtkView.device else {
            fatalError("No MTLDevice on this MTKView.")
        }
        self.device = device
        
        // Charge metal library
        let library = device.makeDefaultLibrary()
        
        // Instantiate the sub-renderers
        self.triangleRenderer = TriangleRenderer(device: device, library: library)
        self.polygonRenderer = PolygonRenderer(device: device, library: library)
        self.pointsRenderer = PointsRenderer(device: device, library: library)
        
        super.init()
        
        // Init ressources
        buildResources()
    }
    
    private func buildResources() {
        commandQueue = device.makeCommandQueue()
        
        // Create a uniformBuffer to store TransformUniforms
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<TransformUniforms>.size,
            options: []
        )
    }
    
    // MARK: - Public
    
    /// Adds a triangulated polygon (via EarClipping) to the PolygonRenderer
    func addPolygon(points: [ECTPoint], color: SIMD4<Float>) {
        polygonRenderer.addPolygon(points: points, color: color)
    }
    
    /// Clear existing polygons from the renderer
    func clearPolygons() {
        polygonRenderer.clearPolygons()
    }
    
    func showTriangle(_ shouldDisplayTriangle: Bool) {
        showTriangle = shouldDisplayTriangle
    }
    
    func setZoomAndPan(zoom: CGFloat, panOffset: CGSize) {
        self.zoom = Float(zoom)
        pan.x = Float(panOffset.width)
        pan.y = Float(panOffset.height)
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // handle resizing if needed
    }
    
    func draw(in view: MTKView) {
        guard
            let passDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandQueue = commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }
        
        updateUniforms()
        
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
        
        // Optional triangle
        if showTriangle {
            triangleRenderer.draw(
                encoder: encoder,
                uniformBuffer: uniformBuffer
            )
        }
        
        // Polygons
        polygonRenderer.draw(
            encoder: encoder,
            uniformBuffer: uniformBuffer
        )
        
        // Preview points
        pointsRenderer?.draw(
            encoder: encoder,
            uniformBuffer: uniformBuffer
        )
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func updateUniforms() {
        // 1) Build the transform matrix from zoom & pan
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
