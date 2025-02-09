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
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported.")
        }
        let mtkView = ZoomableMTKView(frame: .zero, device: device)

        // doc size
        let docWidth = appState.selectedDocument?.width ?? 512
        let docHeight = appState.selectedDocument?.height ?? 512

        let mr = MainMetalRenderer(mtkView: mtkView,
                                   showTriangle: showTriangle,
                                   width: docWidth,
                                   height: docHeight)
        mtkView.delegate = mr

        context.coordinator.mainRenderer = mr
        mtkView.coordinator = context.coordinator

        DispatchQueue.main.async {
            self.appState.mainRenderer = mr
        }

        mtkView.clearColor = appState.selectedBackgroundColor.toMTLClearColor()
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false

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

        mtkView.window?.makeFirstResponder(mtkView)

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.mainRenderer?.previewColor = appState.selectedColor.toSIMD4()
        context.coordinator.mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        context.coordinator.mainRenderer?.showTriangle(showTriangle)

        nsView.clearColor = appState.selectedBackgroundColor.toMTLClearColor()
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

        // MARK: - Pinch Zoom

        @objc func handleMagnification(_ sender: NSMagnificationGestureRecognizer) {
            guard let view = sender.view else { return }
            if sender.state == .changed {
                // 1) The anchor in view coords
                let anchorScreen = sender.location(in: view)

                // 2) Convert to world coords
                let oldZoom = zoom
                let anchorWorld = screenPointToWorld(anchorScreen, in: view, zoom: oldZoom, pan: panOffset)

                // 3) new zoom
                let zoomFactor = 1 + sender.magnification
                sender.magnification = 0
                var newZoom = oldZoom*zoomFactor

                // clamp
                let minZ: CGFloat = 0.1
                let maxZ: CGFloat = 8.0
                newZoom = max(minZ, min(newZoom, maxZ))
                zoom = newZoom

                // 4) anchor in screen after => worldPointToScreen
                let anchorScreenAfter = worldPointToScreen(anchorWorld, in: view, zoom: newZoom, pan: panOffset)
                // difference
                let dx = anchorScreen.x - anchorScreenAfter.x
                let dy = anchorScreen.y - anchorScreenAfter.y

                let size = view.bounds.size
                panOffset.width += dx / size.width
                panOffset.height -= dy / size.height

                mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
            }
        }

        // MARK: - Pan gesture

        @objc func handlePan(_ sender: NSPanGestureRecognizer) {
            let translation = sender.translation(in: sender.view)
            let size = sender.view?.bounds.size ?? .zero
            panOffset.width += translation.x / size.width
            panOffset.height -= translation.y / size.height
            sender.setTranslation(.zero, in: sender.view)
            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }

        // MARK: - Mouse events

        @MainActor func mouseClicked(at nsPoint: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }

            switch tool.name {
            case "Polygone par clic":
                let wpt = screenPointToWorld(nsPoint, in: view, zoom: zoom, pan: panOffset)
                clickedPoints.append(wpt)
                mainRenderer?.pointsRenderer?.updatePreviewPoints(clickedPoints)

            case "Remplissage":
                if appState.pixelFillEnabled {
                    fillTexturePixelByPixel(nsPoint, in: view)
                } else {
                    let wc = screenPointToWorld(nsPoint, in: view, zoom: zoom, pan: panOffset)
                    fillPolygonIfClicked(worldCoords: wc)
                }

            default:
                break
            }
        }

        // MARK: - Key events

        @MainActor func keyPressedEnter() {
            guard let tool = appState.selectedTool else { return }
            if tool.name == "Polygone par clic" {
                if clickedPoints.count>=2 {
                    appState.storePolygonInDocument(clickedPoints, color: appState.selectedColor)
                }
                clickedPoints.removeAll()
                mainRenderer?.pointsRenderer?.updatePreviewPoints([])
            }
        }

        // MARK: - Scroll wheel => we do a "zoom" like pinch?

        func handleScrollWheel(_ event: NSEvent) {
            guard let view = event.window?.contentView else { return }

            // On mac, deltaY>0 => scroll up => zoom in
            // We'll do a factor
            let factor: CGFloat = 0.01
            let zoomFactor = 1 + event.deltaY*factor
            if zoomFactor <= 0 { return }

            // anchor = mouse position in window coords => in local coords
            let anchorInView = view.convert(event.locationInWindow, to: nil)
            // But better: if the user scrolled in the "mtkView"
            if let mtkView = view as? NSView {
                let localPoint = mtkView.convert(event.locationInWindow, from: nil)

                // anchor
                let oldZoom = zoom
                let anchorWorld = screenPointToWorld(localPoint, in: mtkView, zoom: oldZoom, pan: panOffset)
                var newZoom = oldZoom*zoomFactor

                // clamp
                let minZ: CGFloat = 0.1
                let maxZ: CGFloat = 8.0
                newZoom = max(minZ, min(newZoom, maxZ))
                zoom = newZoom

                // anchor after
                let anchorScreenAfter = worldPointToScreen(anchorWorld, in: mtkView, zoom: newZoom, pan: panOffset)
                let dx = localPoint.x - anchorScreenAfter.x
                let dy = localPoint.y - anchorScreenAfter.y

                let size = mtkView.bounds.size
                panOffset.width += dx / size.width
                panOffset.height -= dy / size.height

                mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
            }
        }

        // MARK: - fill polygon

        @MainActor private func fillPolygonIfClicked(worldCoords: ECTPoint) {
            guard let doc = appState.selectedDocument else { return }
            var polys = doc.loadAllPolygons()
            if polys.isEmpty { return }

            for i in 0..<polys.count {
                let sp = polys[i]
                if isPointInPolygon(worldCoords, polygon: sp.points) {
                    var updated = FillAlgorithms.fillPolygonVector(sp, with: appState.fillAlgorithm, color: appState.selectedColor)
                    polys[i] = updated
                    doc.saveAllPolygons(polys)

                    mainRenderer?.clearPolygons()
                    for p in polys {
                        let epts = p.points.map { ECTPoint(x: $0.x, y: $0.y) }
                        let c = SIMD4<Float>(p.color[0], p.color[1], p.color[2], p.color[3])
                        mainRenderer?.addPolygon(points: epts, color: c)
                    }
                    return
                }
            }
        }

        // MARK: - fill texture

        @MainActor private func fillTexturePixelByPixel(_ nsPoint: NSPoint, in view: NSView) {
            guard let mr = mainRenderer else { return }
            guard let tex = mr.fillTexture,
                  var buf = mr.cpuBuffer
            else { return }

            let size = view.bounds.size
            let tx = Int(nsPoint.x*CGFloat(tex.width) / size.width)
            let ty = Int((size.height - nsPoint.y)*CGFloat(tex.height) / size.height)

            if tx < 0||tx>=tex.width||ty < 0||ty>=tex.height { return }

            tex.getBytes(&buf,
                         bytesPerRow: tex.width*4,
                         from: MTLRegionMake2D(0, 0, tex.width, tex.height),
                         mipmapLevel: 0)

            FillAlgorithms.fillPixels(buffer: &buf,
                                      width: tex.width,
                                      height: tex.height,
                                      startX: tx,
                                      startY: ty,
                                      fillAlgo: appState.fillAlgorithm,
                                      fillColor: appState.selectedColor)

            tex.replace(region: MTLRegionMake2D(0, 0, tex.width, tex.height),
                        mipmapLevel: 0,
                        withBytes: &buf,
                        bytesPerRow: tex.width*4)

            mr.cpuBuffer = buf
        }

        // MARK: - isPointInPolygon

        private func isPointInPolygon(_ pt: ECTPoint, polygon: [Point2D]) -> Bool {
            let x = pt.x
            let y = pt.y
            var inside = false
            var j = polygon.count - 1
            for i in 0..<polygon.count {
                let xi = polygon[i].x
                let yi = polygon[i].y
                let xj = polygon[j].x
                let yj = polygon[j].y

                let intersect = ((yi>y) != (yj>y)) &&
                    (x < (xj - xi)*(y - yi) / (yj - yi) + xi)
                if intersect { inside.toggle() }
                j = i
            }
            return inside
        }

        // MARK: - Conversion

        /// Convert screen coords -> world coords, given the current zoom & pan
        func screenPointToWorld(_ pt: CGPoint,
                                in view: NSView,
                                zoom: CGFloat,
                                pan: CGSize) -> ECTPoint
        {
            let b = view.bounds
            // normalized in [-1..1]
            let xN = (pt.x / b.width)*2.0 - 1.0
            let yN = (pt.y / b.height)*2.0 - 1.0

            // remove pan
            let tx = Float(pan.width)*2.0
            let ty = Float(-pan.height)*2.0
            var fx = Float(xN) - tx
            var fy = Float(yN) - ty

            // remove zoom
            fx /= Float(zoom)
            fy /= Float(zoom)

            return ECTPoint(x: Double(fx), y: Double(fy))
        }

        /// Convert world coords -> screen coords, with the current (or new) zoom & pan
        func worldPointToScreen(_ wpt: ECTPoint,
                                in view: NSView,
                                zoom: CGFloat,
                                pan: CGSize) -> CGPoint
        {
            // apply zoom
            var fx = Float(wpt.x)*Float(zoom)
            var fy = Float(wpt.y)*Float(zoom)

            // apply pan
            fx += Float(pan.width)*2.0
            fy += Float(-pan.height)*2.0

            // convert to [0..1]
            let b = view.bounds
            let xN = (Double(fx) + 1.0) / 2.0
            let yN = (Double(fy) + 1.0) / 2.0

            let scrX = xN*Double(b.width)
            let scrY = yN*Double(b.height)
            return CGPoint(x: scrX, y: scrY)
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

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 {
                coordinator?.keyPressedEnter()
            } else {
                super.keyDown(with: event)
            }
        }

        override func becomeFirstResponder() -> Bool { true }
    }
}
