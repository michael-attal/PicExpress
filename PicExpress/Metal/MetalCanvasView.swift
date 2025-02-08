//
//  MetalCanvasView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import SwiftUI

struct MetalCanvasView: NSViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var panOffset: CGSize
    
    // To (de)activate the gradient triangle display
    @Binding var showTriangle: Bool
    
    // For storing mainRenderer in appState
    @Environment(AppState.self) private var appState
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoom: $zoom,
            panOffset: $panOffset,
            showTriangle: $showTriangle,
            appState: appState
        )
    }

    func makeNSView(context: Context) -> MTKView {
        // 1. Initializes default device -> done above
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }

        // 2. Instantiates the Metal view
        
        let mtkView = ZoomableMTKView(frame: .zero, device: device)
        
        // 3. Create the main renderer and assign it to coordinator
        let mr = MainMetalRenderer(mtkView: mtkView, showTriangle: showTriangle)
        mtkView.delegate = mr
        
        context.coordinator.mainRenderer = mr
        mtkView.coordinator = context.coordinator // Indispensable for scrollWheel
        
        // Stock into appState needs to go to the main actor for that.
        DispatchQueue.main.async {
            self.appState.mainRenderer = mr
        }
        
        // 4. Background color (black)
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 1)
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        
        // Gestures
        let pinchRecognizer = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnification(_:))
        )
        mtkView.addGestureRecognizer(pinchRecognizer)
        
        let panRecognizer = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        mtkView.addGestureRecognizer(panRecognizer)
        
        // Accept keyDown events
        mtkView.window?.makeFirstResponder(mtkView)
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // On each update, we update the zoom/pan, if we display the triangle renderer and previewColor
        context.coordinator.mainRenderer?.previewColor = appState.selectedColor.toSIMD4()
        context.coordinator.mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        context.coordinator.mainRenderer?.showTriangle(showTriangle)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject {
        @Binding var zoom: CGFloat
        @Binding var panOffset: CGSize
        @Binding var showTriangle: Bool
        
        let appState: AppState
        
        var mainRenderer: MainMetalRenderer?
        
        private var clickedPoints: [ECTPoint] = []
        
        init(
            zoom: Binding<CGFloat>,
            panOffset: Binding<CGSize>,
            showTriangle: Binding<Bool>,
            appState: AppState
        ) {
            self._zoom = zoom
            self._panOffset = panOffset
            self._showTriangle = showTriangle
            self.appState = appState
        }
        
        // MARK: - Magnification (zoom)
        
        @objc func handleMagnification(_ sender: NSMagnificationGestureRecognizer) {
            if sender.state == .changed {
                let zoomFactor = 1 + sender.magnification
                sender.magnification = 0
                zoom *= zoomFactor
                mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
            }
        }
        
        // MARK: - Pan
        
        @objc func handlePan(_ sender: NSPanGestureRecognizer) {
            let translation = sender.translation(in: sender.view)
            let viewSize = sender.view?.bounds.size ?? .zero
            
            // We add the translation in normalized screen space
            panOffset.width += translation.x / viewSize.width
            // Note: we invert translation.y so that dragging “up” is a positive shift
            panOffset.height -= translation.y / viewSize.height
            sender.setTranslation(.zero, in: sender.view)
            
            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }
        
        // MARK: - Mouse click => creation of polygon points in "click polygon" mode
        
        @MainActor func mouseClicked(at nsPoint: NSPoint, in view: NSView) {
            // Only record clicks if we are in polygon-click mode for the moment
            guard appState.isClickPolygonMode else { return }
            
            let bounds = view.bounds
            let x = (nsPoint.x / bounds.width) * 2.0 - 1.0
            let y = (nsPoint.y / bounds.height) * 2.0 - 1.0
            
            // Invert the transform T*S => M^-1 = S^-1 * T^-1
            let s = Float(zoom)
            let tx = Float(panOffset.width) * 2.0
            let ty = Float(-panOffset.height) * 2.0
            
            // Translation inverse
            var finalX = Float(x) - tx
            var finalY = Float(y) - ty
            
            // Scale inverse
            finalX /= s
            finalY /= s
            
            let p = ECTPoint(x: Double(finalX), y: Double(finalY))
            clickedPoints.append(p)
            
            // Update the preview points
            mainRenderer?.pointsRenderer?.updatePreviewPoints(clickedPoints)
        }
        
        // MARK: - Key pressed => validating the polygon
        
        @MainActor func keyPressedEnter() {
            guard appState.isClickPolygonMode else { return }
            
            if clickedPoints.count >= 2 {
                let colorVec = appState.selectedColor.toSIMD4()
                mainRenderer?.addPolygon(points: clickedPoints, color: colorVec)
            }
            
            // Clear the points and hide the preview
            clickedPoints.removeAll()
            mainRenderer?.pointsRenderer?.updatePreviewPoints([])
            
            // Disable the "click polygon" mode
            appState.isClickPolygonMode = false
        }
        
        // MARK: - Scroll wheel => zoom
        
        func handleScrollWheel(_ event: NSEvent) {
            let scrollSensitivity: CGFloat = 0.01
            let zoomFactor = 1 + event.deltaY * scrollSensitivity
            zoom *= zoomFactor
            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }
    }
    
    // MARK: - Custom MTKView to intercept mouse & keyboard events
    
    class ZoomableMTKView: MTKView {
        weak var coordinator: Coordinator?
        
        override func scrollWheel(with event: NSEvent) {
            coordinator?.handleScrollWheel(event)
        }
        
        override func mouseDown(with event: NSEvent) {
            let locationInView = convert(event.locationInWindow, from: nil)
            coordinator?.mouseClicked(at: locationInView, in: self)
        }
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            // keyCode 36 is Enter / Return
            if event.keyCode == 36 {
                coordinator?.keyPressedEnter()
            } else {
                super.keyDown(with: event)
            }
        }
        
        override func becomeFirstResponder() -> Bool {
            return true
        }
    }
}

extension Color {
    /// Convert the SwiftUI color to a SIMD4<Float> in RGBA order
    func toSIMD4() -> SIMD4<Float> {
        let nsColor = NSColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        if let converted = nsColor.usingColorSpace(.deviceRGB) {
            converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        
        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }
}
