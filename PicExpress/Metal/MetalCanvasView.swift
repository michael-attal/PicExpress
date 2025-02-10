//
//  MetalCanvasView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import SwiftUI

/// This struct is the NSViewRepresentable that displays a Metal view
/// and uses a Coordinator to handle input events (mouse, gestures).
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

        // We create the main renderer
        let mr = MainMetalRenderer(mtkView: mtkView,
                                   showTriangle: showTriangle,
                                   width: docWidth,
                                   height: docHeight,
                                   appState: appState)
        mtkView.delegate = mr

        // Store references
        context.coordinator.mainRenderer = mr
        mtkView.coordinator = context.coordinator

        // Also store them in appState
        DispatchQueue.main.async {
            self.appState.mainRenderer = mr
            self.appState.mainCoordinator = context.coordinator
        }

        mtkView.clearColor = appState.selectedBackgroundColor.toMTLClearColor()
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false

        // Add pinch gesture
        let pinchGesture = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnification(_:))
        )
        mtkView.addGestureRecognizer(pinchGesture)

        // Add pan gesture
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

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update transform, color, etc.
        context.coordinator.mainRenderer?.previewColor = appState.selectedColor.toSIMD4()
        context.coordinator.mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        context.coordinator.mainRenderer?.showTriangle(showTriangle)

        nsView.clearColor = appState.selectedBackgroundColor.toMTLClearColor()

        context.coordinator.updatePanGestureEnabled()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        @Binding var zoom: CGFloat
        @Binding var panOffset: CGSize
        @Binding var showTriangle: Bool

        let appState: AppState
        var mainRenderer: MainMetalRenderer?

        var panGesture: NSPanGestureRecognizer?

        /// For "Polygone par clic"
        private var clickedPoints: [ECTPoint] = []

        // For "Formes" creation
        var shapeStart: NSPoint?
        var isDrawingShape: Bool = false
        // We store the shape preview in a points array
        private var shapePreviewPoints: [ECTPoint] = []

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

        /// Enable or disable pan gesture according to the current tool
        @MainActor func updatePanGestureEnabled() {
            guard let panGesture = panGesture else { return }
            guard let tool = appState.selectedTool else {
                panGesture.isEnabled = true
                return
            }
            // We disable pan for "Formes", "Découpage", "Redimensionnement"
            // because we want to avoid conflict with drag of points or shape drawing
            if tool.name == "Formes" || tool.name == "Découpage" || tool.name == "Redimensionnement" {
                panGesture.isEnabled = false
            } else {
                panGesture.isEnabled = true
            }
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
                let anchorAfter = worldPointToScreen(anchorWorld, in: view, zoom: newZoom, pan: panOffset)
                let dx = anchorScreen.x - anchorAfter.x
                let dy = anchorScreen.y - anchorAfter.y

                let size = view.bounds.size
                panOffset.width += dx / size.width
                panOffset.height -= dy / size.height

                mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
            }
        }

        // MARK: - Pan gesture

        @MainActor @objc func handlePan(_ sender: NSPanGestureRecognizer) {
            // We do not do any pan if the tool is "Formes", "Découpage" or "Redimensionnement"
            if let tool = appState.selectedTool,
               tool.name == "Formes" || tool.name == "Découpage" || tool.name == "Redimensionnement"
            {
                return
            }
            let translation = sender.translation(in: sender.view)
            let size = sender.view?.bounds.size ?? .zero
            panOffset.width += translation.x / size.width
            panOffset.height -= translation.y / size.height
            sender.setTranslation(.zero, in: sender.view)
            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }

        // MARK: - Mouse events

        @MainActor func mouseClicked(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }

            switch tool.name {
            case "Polygone par clic":
                // Collect points for a polygon
                let wpt = screenPointToWorld(pt, in: view, zoom: zoom, pan: panOffset)
                clickedPoints.append(wpt)
                mainRenderer?.pointsRenderer?.updatePreviewPoints(clickedPoints)

            case "Découpage":
                // We add points to lassoPoints
                let wpt = screenPointToWorld(pt, in: view, zoom: zoom, pan: panOffset)
                appState.lassoPoints.append(wpt)
                mainRenderer?.pointsRenderer?.updatePreviewPoints(appState.lassoPoints)
                // Also set it as the clip window
                mainRenderer?.setClipWindow(appState.lassoPoints)

            case "Remplissage":
                if appState.pixelFillEnabled {
                    fillTexturePixelByPixel(pt, in: view)
                } else {
                    let wc = screenPointToWorld(pt, in: view, zoom: zoom, pan: panOffset)
                    fillPolygonIfClicked(worldCoords: wc)
                }

            case "Formes":
                // Start drawing a shape
                shapeStart = pt
                isDrawingShape = true
                shapePreviewPoints = []
                mainRenderer?.pointsRenderer?.updatePreviewPoints([])

            case "Gomme":
                let wc = screenPointToWorld(pt, in: view, zoom: zoom, pan: panOffset)
                erasePolygonIfClicked(worldCoords: wc)

            default:
                break
            }
        }

        @MainActor func mouseUp(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            if tool.name == "Formes", isDrawingShape {
                guard let start = shapeStart else { return }
                let end = pt

                let wStart = screenPointToWorld(start, in: view, zoom: zoom, pan: panOffset)
                let wEnd = screenPointToWorld(end, in: view, zoom: zoom, pan: panOffset)

                if let shapeType = appState.currentShapeType {
                    let shapePoints = createShapePolygon(shapeType, start: wStart, end: wEnd)
                    // Store it
                    appState.storePolygonInDocument(shapePoints, color: appState.selectedColor)
                    let c = appState.selectedColor.toSIMD4()
                    mainRenderer?.addPolygon(points: shapePoints, color: c)
                }

                // clear preview
                shapePreviewPoints = []
                mainRenderer?.pointsRenderer?.updatePreviewPoints([])
                shapeStart = nil
                isDrawingShape = false
            }
        }

        @MainActor func mouseDragged(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            if tool.name == "Formes", isDrawingShape {
                // Generate a live preview
                guard let start = shapeStart else { return }
                let wStart = screenPointToWorld(start, in: view, zoom: zoom, pan: panOffset)
                let wCurrent = screenPointToWorld(pt, in: view, zoom: zoom, pan: panOffset)

                if let shapeType = appState.currentShapeType {
                    // Store in preview array
                    let shapePoints = createShapePolygon(shapeType, start: wStart, end: wCurrent)
                    shapePreviewPoints = shapePoints
                    // Display them as points (not lines)
                    mainRenderer?.pointsRenderer?.updatePreviewPoints(shapePreviewPoints)
                }
            }
        }

        override func responds(to aSelector: Selector!) -> Bool {
            return super.responds(to: aSelector)
        }

        // MARK: - Keyboard events

        @MainActor func keyPressedEnter() {
            guard let tool = appState.selectedTool else { return }
            switch tool.name {
            case "Polygone par clic":
                // We store in the document
                if clickedPoints.count >= 3 {
                    appState.storePolygonInDocument(clickedPoints, color: appState.selectedColor)
                }
                clickedPoints.removeAll()
                mainRenderer?.pointsRenderer?.updatePreviewPoints([])

            case "Découpage":
                // The user finishes the lasso => we clip all existing polygons
                if !appState.lassoPoints.isEmpty {
                    performLassoClipping(appState.lassoPoints)
                    appState.lassoPoints.removeAll()
                }
                mainRenderer?.pointsRenderer?.updatePreviewPoints([])
                // Reset window
                mainRenderer?.setClipWindow([])

            default:
                break
            }
        }

        // MARK: - Lasso clipping

        @MainActor func performLassoClipping(_ lasso: [ECTPoint]) {
            // 1) Recover polygons from the document
            guard let doc = appState.selectedDocument else { return }

            var storedPolygons = doc.loadAllPolygons()
            guard !storedPolygons.isEmpty else { return }

            // 2) For each polygon, we clip via the chosen algo
            var newPolys: [StoredPolygon] = []

            for sp in storedPolygons {
                let originalPoints = sp.points.map { ECTPoint(x: $0.x, y: $0.y) }
                let clippedPoints: [ECTPoint]

                switch appState.selectedPolygonAlgorithm {
                case .earClipping:
                    // Not a real clipping => keep original - We should not go in that case since I removed it from the options selection of the sheet view when selecting the "Découpage" tool.
                    clippedPoints = originalPoints

                case .cyrusBeck:
                    // handle concave window if needed
                    clippedPoints = clipWithConcaveWindowIfNeeded(subjectPolygon: originalPoints,
                                                                  window: lasso)

                case .sutherlandHodgman:
                    clippedPoints = clipWithConcaveWindowIfNeeded(subjectPolygon: originalPoints,
                                                                  window: lasso)
                }

                if clippedPoints.count >= 3 {
                    let newPoly = StoredPolygon(
                        points: clippedPoints.map { Point2D(x: $0.x, y: $0.y) },
                        color: sp.color
                    )
                    newPolys.append(newPoly)
                } else {
                    // If the polygon is completely outside => we re-add the original
                    // so it is NOT removed. This is the "ignore the removal" approach.
                    newPolys.append(sp)
                }
            }

            // Save newPolys
            doc.saveAllPolygons(newPolys)

            // Clear & redraw
            mainRenderer?.clearPolygons()
            for p in newPolys {
                let epts = p.points.map { ECTPoint(x: $0.x, y: $0.y) }
                let c = SIMD4<Float>(p.color[0], p.color[1], p.color[2], p.color[3])
                mainRenderer?.addPolygon(points: epts, color: c)
            }
        }

        // MARK: - Scroll => Zoom

        func handleScrollWheel(_ event: NSEvent) {
            guard let view = event.window?.contentView else { return }
            let factor: CGFloat = 0.01
            let zoomFactor = 1 + event.deltaY*factor
            if zoomFactor <= 0 { return }
            let oldZoom = zoom
            if let mtkView = view as? NSView {
                let localPoint = mtkView.convert(event.locationInWindow, from: nil)
                let anchorWorld = screenPointToWorld(localPoint, in: mtkView, zoom: oldZoom, pan: panOffset)
                var newZoom = oldZoom*zoomFactor
                let minZ: CGFloat = 0.1
                let maxZ: CGFloat = 8.0
                newZoom = max(minZ, min(newZoom, maxZ))
                zoom = newZoom

                let anchorAfter = worldPointToScreen(anchorWorld, in: mtkView, zoom: newZoom, pan: panOffset)
                let dx = localPoint.x - anchorAfter.x
                let dy = localPoint.y - anchorAfter.y

                let size = mtkView.bounds.size
                panOffset.width += dx / size.width
                panOffset.height -= dy / size.height

                mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
            }
        }

        // MARK: - fill polygon if clicked

        @MainActor private func fillPolygonIfClicked(worldCoords: ECTPoint) {
            guard let doc = appState.selectedDocument else { return }
            var polys = doc.loadAllPolygons()
            if polys.isEmpty { return }

            for i in 0..<polys.count {
                let sp = polys[i]
                if isPointInPolygon(worldCoords, polygon: sp.points) {
                    let updated = FillAlgorithms.fillPolygonVector(sp,
                                                                   with: appState.fillAlgorithm,
                                                                   color: appState.selectedColor)
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

        // MARK: - erase polygon

        @MainActor private func erasePolygonIfClicked(worldCoords: ECTPoint) {
            guard let doc = appState.selectedDocument else { return }
            var polys = doc.loadAllPolygons()
            if polys.isEmpty { return }

            for i in 0..<polys.count {
                let sp = polys[i]
                if isPointInPolygon(worldCoords, polygon: sp.points) {
                    polys.remove(at: i)
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

        // MARK: - fill texture pixel by pixel

        @MainActor private func fillTexturePixelByPixel(_ nsPoint: NSPoint, in view: NSView) {
            guard let mr = mainRenderer else { return }
            guard let tex = mr.fillTexture,
                  var buf = mr.cpuBuffer
            else { return }

            let size = view.bounds.size
            let tx = Int(nsPoint.x*CGFloat(tex.width) / size.width)
            let ty = Int((size.height - nsPoint.y)*CGFloat(tex.height) / size.height)
            if tx < 0 || tx >= tex.width || ty < 0 || ty >= tex.height { return }

            // If .gpuFragment mode => “fillPolygonOnGPU”.
            if appState.fillAlgorithm == .gpuFragment {
                let polys = appState.selectedDocument?.loadAllPolygons() ?? []
                // Find the polygon containing (tx,ty)
                let ept = ECTPoint(x: Double(tx), y: Double(ty))
                for sp in polys {
                    if isPointInPolygon(ept, polygon: sp.points) {
                        // Convert to [SIMD2<Float>]
                        let floatPoints = sp.points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
                        // color
                        let c4 = appState.selectedColor.toSIMD4()
                        // GPU
                        mr.fillPolygonOnGPU(polygonPoints: floatPoints, color: c4)
                        return
                    }
                }
                print("No polygon found => no gpu fill.")
                return
            }

            // Sinon, mode CPU => on lit, on appelle FillAlgorithms.fillPixels...
            tex.getBytes(&buf,
                         bytesPerRow: tex.width*4,
                         from: MTLRegionMake2D(0, 0, tex.width, tex.height),
                         mipmapLevel: 0)
            FillAlgorithms.fillPixels(
                buffer: &buf,
                width: tex.width,
                height: tex.height,
                startX: tx,
                startY: ty,
                fillAlgo: appState.fillAlgorithm,
                fillColor: appState.selectedColor,
                polygons: appState.selectedDocument?.loadAllPolygons()
            )
            tex.replace(region: MTLRegionMake2D(0, 0, tex.width, tex.height),
                        mipmapLevel: 0,
                        withBytes: &buf,
                        bytesPerRow: tex.width*4)
            mr.cpuBuffer = buf
        }

        // MARK: - Helpers

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

                let intersect = ((yi > y) != (yj > y)) &&
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
            // normalized [-1..1]
            let xN = (pt.x / b.width)*2.0 - 1.0
            let yN = (pt.y / b.height)*2.0 - 1.0

            let tx = Float(pan.width)*2.0
            let ty = Float(-pan.height)*2.0
            var fx = Float(xN) - tx
            var fy = Float(yN) - ty

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

        // MARK: - Shape generation

        private func createShapePolygon(_ shapeType: ShapeType,
                                        start: ECTPoint,
                                        end: ECTPoint) -> [ECTPoint]
        {
            let minX = min(start.x, end.x)
            let maxX = max(start.x, end.x)
            let minY = min(start.y, end.y)
            let maxY = max(start.y, end.y)

            switch shapeType {
            case .rectangle:
                return [
                    ECTPoint(x: minX, y: minY),
                    ECTPoint(x: maxX, y: minY),
                    ECTPoint(x: maxX, y: maxY),
                    ECTPoint(x: minX, y: maxY)
                ]
            case .square:
                let side = max(maxX - minX, maxY - minY)
                let minX2 = start.x < end.x ? start.x : end.x
                let minY2 = start.y < end.y ? start.y : end.y
                return [
                    ECTPoint(x: minX2, y: minY2),
                    ECTPoint(x: minX2 + side, y: minY2),
                    ECTPoint(x: minX2 + side, y: minY2 + side),
                    ECTPoint(x: minX2, y: minY2 + side)
                ]
            case .circle:
                let rx = (maxX - minX)*0.5
                let ry = (maxY - minY)*0.5
                let cx = (maxX + minX)*0.5
                let cy = (maxY + minY)*0.5
                let r = min(rx, ry)
                return approximateEllipse(center: ECTPoint(x: cx, y: cy),
                                          rx: r, ry: r, segments: 32)
            case .ellipse:
                let cx = (maxX + minX)*0.5
                let cy = (maxY + minY)*0.5
                let rx = (maxX - minX)*0.5
                let ry = (maxY - minY)*0.5
                return approximateEllipse(center: ECTPoint(x: cx, y: cy),
                                          rx: rx, ry: ry, segments: 32)
            case .triangle:
                let midX = (minX + maxX)*0.5
                return [
                    ECTPoint(x: midX, y: maxY),
                    ECTPoint(x: minX, y: minY),
                    ECTPoint(x: maxX, y: minY)
                ]
            }
        }

        private func approximateEllipse(center: ECTPoint,
                                        rx: Double,
                                        ry: Double,
                                        segments: Int) -> [ECTPoint]
        {
            var pts: [ECTPoint] = []
            let twoPi = 2.0*Double.pi
            for i in 0..<segments {
                let theta = twoPi*Double(i) / Double(segments)
                let x = center.x + rx*cos(theta)
                let y = center.y + ry*sin(theta)
                pts.append(ECTPoint(x: x, y: y))
            }
            return pts
        }

        @MainActor func clipWithConcaveWindowIfNeeded(subjectPolygon: [ECTPoint],
                                                      window: [ECTPoint]) -> [ECTPoint]
        {
            let clipped = clipWithConcaveWindow(subjectPolygon: subjectPolygon,
                                                windowPolygon: window,
                                                algo: appState.selectedPolygonAlgorithm)
            return clipped
        }
    }

    // MARK: - The actual NSView (subclass)

    class ZoomableMTKView: MTKView {
        weak var coordinator: Coordinator?

        private var draggedVertexIndex: Int? = nil
        private let vertexHitThreshold: CGFloat = 10.0

        override func scrollWheel(with event: NSEvent) {
            coordinator?.handleScrollWheel(event)
        }

        override func mouseDown(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)

            // If the tool is "Redimensionnement", let's try to drag a vertex
            if let tool = coordinator?.appState.selectedTool,
               tool.name == "Redimensionnement"
            {
                let points = coordinator?.appState.lassoPoints ?? []
                for (i, wpt) in points.enumerated() {
                    if let sp = coordinator?.worldPointToScreen(wpt, in: self,
                                                                zoom: coordinator?.zoom ?? 1.0,
                                                                pan: coordinator?.panOffset ?? .zero)
                    {
                        let dx = sp.x - loc.x
                        let dy = sp.y - loc.y
                        let dist = sqrt(dx*dx + dy*dy)
                        if dist < vertexHitThreshold {
                            draggedVertexIndex = i
                            return
                        }
                    }
                }
            }

            // Otherwise => normal
            coordinator?.mouseClicked(at: loc, in: self)
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            let loc = convert(event.locationInWindow, from: nil)

            // If we are dragging a vertex => update the position
            if let idx = draggedVertexIndex {
                let wpt = coordinator?.screenPointToWorld(loc, in: self,
                                                          zoom: coordinator?.zoom ?? 1.0,
                                                          pan: coordinator?.panOffset ?? .zero)
                if let newPt = wpt {
                    coordinator?.appState.lassoPoints[idx] = newPt
                    // Re-run the clipping => but re-add original if outside
                    coordinator?.performLassoClipping(coordinator?.appState.lassoPoints ?? [])

                    coordinator?.mainRenderer?.setClipWindow(coordinator?.appState.lassoPoints ?? [])
                    setNeedsDisplay(bounds)
                }
            } else {
                // normal logic
                coordinator?.mouseDragged(at: loc, in: self)
            }
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            draggedVertexIndex = nil
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

        override func becomeFirstResponder() -> Bool { true }
    }
}
