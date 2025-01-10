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
    let showTriangle: Bool
    
    // For storing mainRenderer in appState
    @Environment(AppState.self) private var appState
    
    func makeCoordinator() -> Coordinator {
        Coordinator(zoom: $zoom, panOffset: $panOffset)
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
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // On each update, we update the zoom/pan
        context.coordinator.mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject {
        @Binding var zoom: CGFloat
        @Binding var panOffset: CGSize
        
        var mainRenderer: MainMetalRenderer?
        
        init(zoom: Binding<CGFloat>, panOffset: Binding<CGSize>) {
            self._zoom = zoom
            self._panOffset = panOffset
        }
        
        @objc func handleMagnification(_ sender: NSMagnificationGestureRecognizer) {
            if sender.state == .changed {
                let zoomFactor = 1 + sender.magnification
                sender.magnification = 0
                zoom *= zoomFactor
                mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
            }
        }
        
        @objc func handlePan(_ sender: NSPanGestureRecognizer) {
            let translation = sender.translation(in: sender.view)
            let viewSize = sender.view?.bounds.size ?? .zero
            
            panOffset.width += translation.x / viewSize.width
            panOffset.height -= translation.y / viewSize.height
            sender.setTranslation(.zero, in: sender.view)
            
            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }
        
        func handleScrollWheel(_ event: NSEvent) {
            let scrollSensitivity: CGFloat = 0.01
            let zoomFactor = 1 + event.deltaY * scrollSensitivity
            zoom *= zoomFactor
            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }
    }
    
    // MARK: - ZoomableMTKView
    
    class ZoomableMTKView: MTKView {
        weak var coordinator: Coordinator?
        
        override func scrollWheel(with event: NSEvent) {
            coordinator?.handleScrollWheel(event)
        }
    }
}
