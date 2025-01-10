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

        // Link the coordinator
        mtkView.coordinator = context.coordinator

        // 3. Background color (black)
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 1)

        // 4. Create the renderer and assign it as a delegate
        let renderer = MetalRenderer(mtkView: mtkView)
        mtkView.delegate = renderer

        // 5. Store the renderer in the Coordinator
        context.coordinator.renderer = renderer

        // Add gesture recognizers
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

        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Handle update later here if needed
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        @Binding var zoom: CGFloat
        @Binding var panOffset: CGSize

        var renderer: MetalRenderer?

        init(zoom: Binding<CGFloat>, panOffset: Binding<CGSize>) {
            self._zoom = zoom
            self._panOffset = panOffset
        }

        // Pinch
        @objc func handleMagnification(_ sender: NSMagnificationGestureRecognizer) {
            if sender.state == .changed {
                let zoomFactor = 1 + sender.magnification
                sender.magnification = 0
                zoom *= zoomFactor
                renderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
            }
        }

        // Pan
        @objc func handlePan(_ sender: NSPanGestureRecognizer) {
            let translation = sender.translation(in: sender.view)
            let viewSize = sender.view?.bounds.size ?? .zero

            panOffset.width += translation.x / viewSize.width
            panOffset.height -= translation.y / viewSize.height
            sender.setTranslation(.zero, in: sender.view)

            renderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }

        // ScrollWheel
        func handleScrollWheel(_ event: NSEvent) {
            let scrollSensitivity: CGFloat = 0.01
            let zoomFactor = 1 + event.deltaY * scrollSensitivity

            zoom *= zoomFactor
            renderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }
    }

    // MARK: - Custom Zoomable MTKView

    class ZoomableMTKView: MTKView {
        weak var coordinator: Coordinator?

        override func scrollWheel(with event: NSEvent) {
            coordinator?.handleScrollWheel(event)
        }
    }
}
