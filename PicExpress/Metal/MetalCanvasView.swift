//
//  MetalCanvasView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import SwiftUI

/// A SwiftUI NSViewRepresentable that hosts an MTKView and uses a Coordinator
/// to handle zoom, pan, and user interactions.
struct MetalCanvasView: NSViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var panOffset: CGSize

    @Environment(AppState.self) private var appState

    // MARK: - makeCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoom: $zoom,
            panOffset: $panOffset,
            appState: appState
        )
    }

    // MARK: - makeNSView

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported.")
        }

        let mtkView = ZoomableMTKView(frame: .zero, device: device)
        mtkView.framebufferOnly = false

        // Create the main renderer
        let mr = MainMetalRenderer(
            mtkView: mtkView,
            width: appState.selectedDocument?.width ?? 512,
            height: appState.selectedDocument?.height ?? 512
        )
        mtkView.delegate = mr

        // Store references
        context.coordinator.metalView = mtkView
        context.coordinator.mainRenderer = mr
        mtkView.coordinator = context.coordinator

        // Place in AppState
        DispatchQueue.main.async {
            self.appState.mainRenderer = mr
            self.appState.mainCoordinator = context.coordinator

            // We calculate and assign the initial zoom
            if let doc = self.appState.selectedDocument {
                let docW = CGFloat(doc.width)
                let docH = CGFloat(doc.height)
                let viewW = mtkView.bounds.width
                let viewH = mtkView.bounds.height

                guard docW > 0, docH > 0, viewW > 0, viewH > 0 else { return }

                // Calculation of the ratio => Doc in the view
                let ratioW = viewW / docW
                let ratioH = viewH / docH
                let bestFitZoom = min(ratioW, ratioH)

                self.zoom = bestFitZoom
                self.panOffset = .zero

                mr.setZoomAndPan(zoom: self.zoom, panOffset: self.panOffset)
            }
        }

        // Configure clearColor, etc.
        mtkView.clearColor = appState.selectedBackgroundColor.toMTLClearColor()
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false

        // Gestures: pinch => zoom, pan => translation
        let pinchGesture = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnification(_:))
        )
        mtkView.addGestureRecognizer(pinchGesture)

        let panGesture = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        mtkView.addGestureRecognizer(panGesture)
        context.coordinator.panGesture = panGesture
        context.coordinator.updatePanGestureEnabled()

        // Make this view first responder so it can receive key events
        mtkView.window?.makeFirstResponder(mtkView)

        return mtkView
    }

    // MARK: - updateNSView

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update transform, color, etc.
        context.coordinator.mainRenderer?.previewColor = appState.selectedColor.toSIMD4()
        context.coordinator.mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)

        nsView.clearColor = appState.selectedBackgroundColor.toMTLClearColor()
        context.coordinator.updatePanGestureEnabled()
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject {
        @Binding var zoom: CGFloat
        @Binding var panOffset: CGSize

        let appState: AppState
        var mainRenderer: MainMetalRenderer?
        weak var metalView: MTKView?

        var panGesture: NSPanGestureRecognizer?

        /// Initialize with references to zoom and panOffset (two-way bindings), plus the global AppState.
        init(
            zoom: Binding<CGFloat>,
            panOffset: Binding<CGSize>,
            appState: AppState
        ) {
            self._zoom = zoom
            self._panOffset = panOffset
            self.appState = appState
        }

        // MARK: - Update pan gesture enabled/disabled

        /// Called whenever we want to enable/disable panning (drag) according to the selected tool.
        func updatePanGestureEnabled() {
            guard let panGesture = panGesture else { return }
            guard let tool = appState.selectedTool else {
                panGesture.isEnabled = true
                return
            }
            // Only enable pan if the user is in "freeMove" tool
            panGesture.isEnabled = (tool == .freeMove)
        }

        // MARK: - Zoom clamping

        /// Clamp the zoom so that the doc does not exceed the size of the MetalCanvasView.
        /// For example, docWidth = 512, viewWidth = 800 => max zoom = 800/512.
        private func clampZoom(to newZoom: CGFloat) -> CGFloat {
            guard let metalView = metalView else { return newZoom }
            guard let doc = appState.selectedDocument else { return newZoom }

            let docW = CGFloat(doc.width)
            let docH = CGFloat(doc.height)
            let viewW = metalView.bounds.width
            let viewH = metalView.bounds.height

            // If any dimension is zero => do not clamp
            guard docW > 0, docH > 0, viewW > 0, viewH > 0 else {
                return newZoom
            }

            // ratioW = how much we can zoom so docWidth <= viewWidth
            let ratioW = viewW / docW
            // ratioH = how much we can zoom so docHeight <= viewHeight
            let ratioH = viewH / docH
            // We pick the smallest => doc fully fits in the view
            let maxZoom = min(ratioW, ratioH)

            let minZoom: CGFloat = 0.1
            let clamped = max(minZoom, min(newZoom, maxZoom))
            return clamped
        }

        // MARK: - Pan clamping

        /// We clamp the pan so the entire doc stays within [-1..+1] in NDC, if zoom>1.
        /// If zoom <= 1 => we center at zero (no pan).
        private func clampPanOffset(_ offset: CGSize, zoom s: CGFloat) -> CGSize {
            // If s <= 1 => doc is smaller than the view => we keep it centered => .zero
            guard s > 1 else {
                return .zero
            }
            // doc in NDC goes from -s..+s, we want to keep that in [-1..+1]
            // => -s + tx >= -1 => tx >= -1 + s
            // => +s + tx <= +1 => tx <= +1 - s
            // => tx in [s-1.. 1-s]
            // But we store tx = pan.x * 2.0 in the shader => pan.x = tx/2
            // So we solve in the same manner, or do direct approach:
            // We'll consider "half = s" => the doc extends from -s..+s in NDC. We want it inside -1..+1.
            let half = s
            // minVal = ( half - 1 ) / 2
            // maxVal = ( 1 - half ) / 2
            let minVal = (half - 1.0) / 2.0
            let maxVal = (1.0 - half) / 2.0
            // Possibly minVal > maxVal if s>1 => reorder them
            let rmin = min(minVal, maxVal) // could be negative
            let rmax = max(minVal, maxVal)

            var newOffset = offset
            // clamp width
            if newOffset.width < rmin { newOffset.width = rmin }
            if newOffset.width > rmax { newOffset.width = rmax }
            // clamp height
            if newOffset.height < rmin { newOffset.height = rmin }
            if newOffset.height > rmax { newOffset.height = rmax }

            return newOffset
        }

        // MARK: - Pinch Zoom

        @objc
        func handleMagnification(_ sender: NSMagnificationGestureRecognizer) {
            if sender.state == .changed {
                // factor = 1 + pinchDelta
                let factor = 1 + sender.magnification
                sender.magnification = 0

                // Multiply current zoom
                var newZoom = zoom * factor
                // Then clamp
                newZoom = clampZoom(to: newZoom)

                zoom = newZoom

                // After zoom changed => clamp pan
                panOffset = clampPanOffset(panOffset, zoom: zoom)
                mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
            }
        }

        // MARK: - Pan gesture

        @objc
        func handlePan(_ sender: NSPanGestureRecognizer) {
            guard appState.selectedTool == .freeMove else { return }

            let translation = sender.translation(in: sender.view)
            let size = sender.view?.bounds.size ?? .zero

            // We invert Y => dragging up => panOffset.height > 0
            panOffset.width += translation.x / size.width
            panOffset.height -= translation.y / size.height

            // Then clamp so doc does not go out of bounds
            panOffset = clampPanOffset(panOffset, zoom: zoom)

            sender.setTranslation(.zero, in: sender.view)
            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }

        // MARK: - Scroll Wheel => Zoom

        func handleScrollWheel(_ event: NSEvent) {
            guard appState.selectedTool == .freeMove else { return }

            let oldZoom = zoom
            let zoomFactor: CGFloat = 1.1

            if event.deltaY > 0 {
                // scroll up => zoom in
                zoom = clampZoom(to: oldZoom * zoomFactor)
            } else if event.deltaY < 0 {
                // scroll down => zoom out
                zoom = clampZoom(to: oldZoom / zoomFactor)
            }

            // clamp pan again
            panOffset = clampPanOffset(panOffset, zoom: zoom)

            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }

        // MARK: - Mouse & keyboard placeholders

        /// Called when the user clicks the left mouse button
        func mouseClicked(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            switch tool {
            case .addPolygonFromClick:
                guard let mr = mainRenderer else { return }
                guard let doc = appState.selectedDocument else { return }

                let viewSize = view.bounds.size
                if viewSize.width <= 0 || viewSize.height <= 0 { return }

                // Convert to NDC [-1..1], with no Y inversion:
                let ndcX = Float((pt.x / viewSize.width) * 2.0 - 1.0)
                let ndcY = Float((pt.y / viewSize.height) * 2.0 - 1.0)
                let ndcPos = simd_float4(ndcX, ndcY, 0, 1)

                // Invert the renderer's transform
                let invTransform = simd_inverse(mr.currentTransform)
                let docNdcPos = invTransform * ndcPos

                // docNdc => pixel coords
                let docW = Float(doc.width)
                let docH = Float(doc.height)

                let docNdcX = docNdcPos.x / docNdcPos.w
                let docNdcY = docNdcPos.y / docNdcPos.w

                let px = (docNdcX + 1) * 0.5 * docW
                let py = (docNdcY + 1) * 0.5 * docH

                let newPoint = ECTPoint(x: Double(px), y: Double(py))
                appState.lassoPoints.append(newPoint)

                // Update preview
                mr.updatePreviewPoints(appState.lassoPoints)

            default:
                // For other tools, do nothing or custom logic
                break
            }
        }

        func mouseDragged(at pt: NSPoint, in view: NSView) {
            // If we need something for shapes or resizing
        }

        func mouseUp(at pt: NSPoint, in view: NSView) {
            // finalize shape or something
        }

        /// Called when user presses Enter
        func keyPressedEnter() {
            guard let tool = appState.selectedTool else { return }
            switch tool {
            case .addPolygonFromClick:
                // If at least 3 points => triangulate
                if appState.lassoPoints.count >= 3 {
                    guard let doc = appState.selectedDocument else { return }
                    guard let mr = mainRenderer else { return }

                    let oldMesh = doc.loadMesh()
                    var oldVertices: [PolygonVertex] = []
                    var oldIndices: [UInt16] = []
                    if let (ov, oi) = oldMesh {
                        oldVertices = ov
                        oldIndices = oi
                    }

                    let color = appState.selectedColor
                    let (newVertices, newIndices) = EarClippingTriangulation.earClipOnePolygon(
                        ectPoints: appState.lassoPoints,
                        color: color,
                        existingVertexCount: oldVertices.count
                    )

                    let mergedVertices = oldVertices + newVertices
                    let mergedIndices = oldIndices + newIndices

                    doc.saveMesh(mergedVertices, mergedIndices)
                    mr.meshRenderer.updateMesh(vertices: mergedVertices, indices: mergedIndices)
                }

                // Clear the lassoPoints + preview
                appState.lassoPoints.removeAll()
                mainRenderer?.updatePreviewPoints([])

            default:
                break
            }
        }
    }

    // MARK: - ZoomableMTKView

    class ZoomableMTKView: MTKView {
        weak var coordinator: Coordinator?

        override func scrollWheel(with event: NSEvent) {
            coordinator?.handleScrollWheel(event)
        }

        override func mouseDown(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            coordinator?.mouseClicked(at: loc, in: self)
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            let loc = convert(event.locationInWindow, from: nil)
            coordinator?.mouseDragged(at: loc, in: self)
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            let loc = convert(event.locationInWindow, from: nil)
            coordinator?.mouseUp(at: loc, in: self)
        }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            // Enter => keyCode = 36
            if event.keyCode == 36 {
                coordinator?.keyPressedEnter()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
