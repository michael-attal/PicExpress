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

    // MARK: - makeCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoom: $zoom,
            panOffset: $panOffset,
            showTriangle: $showTriangle,
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

        // Retrieve the doc size
        let docWidth = appState.selectedDocument?.width ?? 512
        let docHeight = appState.selectedDocument?.height ?? 512

        // Create the main renderer
        let mr = MainMetalRenderer(
            mtkView: mtkView,
            showTriangle: showTriangle,
            width: docWidth,
            height: docHeight,
            appState: appState
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
        }

        // Config
        mtkView.clearColor = appState.selectedBackgroundColor.toMTLClearColor()
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false

        // Gestures: pinch => zoom, pan => translation
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

    // MARK: - updateNSView

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update transform, color, etc.
        context.coordinator.mainRenderer?.previewColor = appState.selectedColor.toSIMD4()
        context.coordinator.mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        context.coordinator.mainRenderer?.showTriangle(showTriangle)

        nsView.clearColor = appState.selectedBackgroundColor.toMTLClearColor()

        context.coordinator.updatePanGestureEnabled()
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject {
        @Binding var zoom: CGFloat
        @Binding var panOffset: CGSize
        @Binding var showTriangle: Bool

        let appState: AppState
        var mainRenderer: MainMetalRenderer?
        weak var metalView: MTKView?

        var panGesture: NSPanGestureRecognizer?

        /// For "Polygone par clic"
        private var clickedPoints: [ECTPoint] = []
        // For "Formes" creation
        var shapeStart: NSPoint?
        var isDrawingShape: Bool = false
        // We store the shape preview in a points array
        private var shapePreviewPoints: [ECTPoint] = []

        // For Redimensionnement
        private var draggedPolygonIndex: Int?
        private var draggedVertexIndex: Int?

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

        // Enable/disable pan
        @MainActor func updatePanGestureEnabled() {
            guard let panGesture = panGesture else { return }
            guard let tool = appState.selectedTool else {
                panGesture.isEnabled = true
                return
            }
            // We disable pan for "Formes", "Découpage", "Redimensionnement"
            // because we want to avoid conflict with drag of points or shape drawing
            if tool.name == "Formes"
                || tool.name == "Découpage"
                || tool.name == "Redimensionnement"
            {
                panGesture.isEnabled = false
            } else {
                panGesture.isEnabled = true
            }
        }

        // MARK: - Pinch Zoom

        @objc func handleMagnification(_ sender: NSMagnificationGestureRecognizer) {
            guard let view = sender.view else { return }
            if sender.state == .changed {
                let oldZoom = zoom
                let factor = 1 + sender.magnification
                sender.magnification = 0
                var newZoom = oldZoom*factor
                newZoom = max(0.1, min(newZoom, 8.0))
                zoom = newZoom
            }
        }

        // MARK: - Pan gesture

        @MainActor @objc func handlePan(_ sender: NSPanGestureRecognizer) {
            // We do not do any pan if the tool is "Formes", "Découpage" or "Redimensionnement"
            if let tool = appState.selectedTool,
               tool.name == "Formes"
               || tool.name == "Découpage"
               || tool.name == "Redimensionnement"
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

        override func responds(to aSelector: Selector!) -> Bool {
            return super.responds(to: aSelector)
        }

        // MARK: - Mouse / keyboard

        @MainActor func mouseClicked(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            guard let doc = appState.selectedDocument else { return }

            let pixel = screenPointToPixel(pt, in: view, docWidth: doc.width, docHeight: doc.height)

            switch tool.name {
            case "Polygone par clic":
                clickedPoints.append(pixel)
                mainRenderer?.pointsRenderer?.updatePreviewPoints(clickedPoints)

            case "Découpage":
                appState.lassoPoints.append(pixel)
                mainRenderer?.pointsRenderer?.updatePreviewPoints(appState.lassoPoints)
                mainRenderer?.setClipWindow(appState.lassoPoints)

            case "Remplissage":
                if appState.fillAlgorithm == .defaultPipelineGPU {
                    fillPolygonVectorIfClicked(pixel)
                } else {
                    fillTexturePixelByPixel(pixel)
                }

            case "Formes":
                shapeStart = pt
                isDrawingShape = true
                shapePreviewPoints = []
                mainRenderer?.pointsRenderer?.updatePreviewPoints([])

            case "Gomme":
                erasePolygonIfClicked(pixel)

            case "Redimensionnement":
                let polygons = doc.loadAllPolygons()
                if polygons.isEmpty { return }
                var bestDist = Double.greatestFiniteMagnitude
                var bestPoly = -1
                var bestVertex = -1

                for (pi, storedPoly) in polygons.enumerated() {
                    for (vi, v) in storedPoly.points.enumerated() {
                        let dx = pixel.x - v.x
                        let dy = pixel.y - v.y
                        let dist = sqrt(dx*dx + dy*dy)
                        if dist < bestDist {
                            bestDist = dist
                            bestPoly = pi
                            bestVertex = vi
                        }
                    }
                }
                if bestDist < 10.0, bestPoly >= 0, bestVertex >= 0 {
                    draggedPolygonIndex = bestPoly
                    draggedVertexIndex = bestVertex
                } else {
                    draggedPolygonIndex = nil
                    draggedVertexIndex = nil
                }

            default:
                break
            }
        }

        @MainActor func mouseUp(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            guard let doc = appState.selectedDocument else { return }

            let pixel = screenPointToPixel(pt, in: view, docWidth: doc.width, docHeight: doc.height)

            if tool.name == "Formes", isDrawingShape {
                guard let start = shapeStart else { return }
                let startPix = screenPointToPixel(start, in: view, docWidth: doc.width, docHeight: doc.height)
                if let shapeType = appState.currentShapeType {
                    let shapePoints = createShapePolygon(shapeType, start: startPix, end: pixel)
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

            // When release the mouse, stop dragging.
            if tool.name == "Redimensionnement" {
                draggedPolygonIndex = nil
                draggedVertexIndex = nil
            }
        }

        @MainActor func mouseDragged(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            guard let doc = appState.selectedDocument else { return }

            let pixel = screenPointToPixel(pt, in: view, docWidth: doc.width, docHeight: doc.height)

            if tool.name == "Formes", isDrawingShape {
                // Generate a live preview
                guard let start = shapeStart else { return }
                let sPix = screenPointToPixel(start, in: view, docWidth: doc.width, docHeight: doc.height)
                if let shapeType = appState.currentShapeType {
                    let shapePoints = createShapePolygon(shapeType, start: sPix, end: pixel)
                    shapePreviewPoints = shapePoints
                    mainRenderer?.pointsRenderer?.updatePreviewPoints(shapePreviewPoints)
                }
            } else if tool.name == "Redimensionnement" {
                guard let dp = draggedPolygonIndex, let dv = draggedVertexIndex else { return }
                var polygons = doc.loadAllPolygons()
                if dp < 0 || dp >= polygons.count { return }
                var sp = polygons[dp]

                var pts = sp.points
                if dv >= 0 && dv < pts.count {
                    pts[dv] = Point2D(x: pixel.x, y: pixel.y)
                    sp = StoredPolygon(
                        points: pts,
                        color: sp.color,
                        polygonTextureData: sp.polygonTextureData,
                        textureWidth: sp.textureWidth,
                        textureHeight: sp.textureHeight
                    )
                    polygons[dp] = sp
                    // Save doc
                    doc.saveAllPolygons(polygons)

                    // Redraw everything
                    mainRenderer?.clearPolygons()
                    reloadPolygonsFromDoc()
                }
            }
        }

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

        // MARK: - fillTexturePixelByPixel

        /**
          Performs a CPU fill via FillAlgorithms, then updates the texture.
          - We identify the clicked polygon
          - We colorize the region
          - Then we do a BFS on all polygons of the same color,
            checking if they are directly or indirectly overlapping
            with the clicked polygon.
          - For each connected polygon, we store the updated doc-size texture.
         */
        @MainActor private func fillTexturePixelByPixel(_ pixel: ECTPoint) {
            guard let mr = mainRenderer,
                  let tex = mr.fillTexture,
                  var buf = mr.cpuBuffer,
                  let doc = appState.selectedDocument else { return }

            let sx = Int(pixel.x)
            let sy = Int(pixel.y)
            if sx < 0 || sx >= tex.width || sy < 0 || sy >= tex.height {
                return
            }

            // 1) Read the CPU buffer from the texture
            tex.getBytes(&buf,
                         bytesPerRow: tex.width*4,
                         from: MTLRegionMake2D(0, 0, tex.width, tex.height),
                         mipmapLevel: 0)

            // 2) Find the clicked polygon
            var polygons = doc.loadAllPolygons()
            if polygons.isEmpty { return }
            var clickedIndex: Int? = nil
            for i in 0..<polygons.count {
                let sp = polygons[i]
                if FillAlgorithms.isPointInPolygon(
                    ECTPoint(x: Double(sx), y: Double(sy)),
                    polygon: sp.points,
                    fillRule: appState.fillRule
                ) {
                    clickedIndex = i
                    break
                }
            }
            guard let cIndex = clickedIndex else {
                // No polygon => do nothing
                return
            }

            let clickedPoly = polygons[cIndex]
            let originalColor = FillAlgorithms.getPixelColor(buf, tex.width, tex.height, sx, sy)
            let newCol = FillAlgorithms.colorToByteTuple(appState.selectedColor)
            if originalColor == newCol {
                // No change
                return
            }

            // 3) CPU fill of the pixel buffer
            FillAlgorithms.fillPixels(
                buffer: &buf,
                width: tex.width,
                height: tex.height,
                startX: sx,
                startY: sy,
                fillAlgo: appState.fillAlgorithm,
                fillColor: appState.selectedColor,
                polygons: polygons,
                fillRule: appState.fillRule
            )

            // 4) Re-upload to the Metal texture
            mr.updateFillTextureCPU(buffer: buf)

            // 5) BFS over polygons that share the same original color.
            //    We recolor all polygons connected (directly or indirectly)
            //    to 'clickedPoly' by superposition.
            let finalBufData = Data(buf)
            let connectedIndices = findConnectedPolygonsIndices(
                polygons: polygons,
                startIndex: cIndex
            )

            for idx in connectedIndices {
                var sp = polygons[idx]
                sp.polygonTextureData = finalBufData
                sp.textureWidth = tex.width
                sp.textureHeight = tex.height
                polygons[idx] = sp
            }

            // Save the updated polygons
            doc.saveAllPolygons(polygons)

            // 6) reload
            reloadPolygonsFromDoc()
        }

        /// fillPolygonVectorIfClicked => simple vector recolor
        @MainActor private func fillPolygonVectorIfClicked(_ pixel: ECTPoint) {
            guard let doc = appState.selectedDocument else { return }
            var polys = doc.loadAllPolygons()
            if polys.isEmpty { return }

            for i in 0..<polys.count {
                let sp = polys[i]
                if FillAlgorithms.isPointInPolygon(
                    pixel,
                    polygon: sp.points,
                    fillRule: appState.fillRule
                ) {
                    let updated = FillAlgorithms.fillPolygonVector(
                        sp,
                        with: appState.fillAlgorithm,
                        color: appState.selectedColor
                    )
                    polys[i] = updated
                    doc.saveAllPolygons(polys)

                    mainRenderer?.clearPolygons()
                    reloadPolygonsFromDoc()
                    return
                }
            }
        }

        /// Eraser
        @MainActor private func erasePolygonIfClicked(_ pixel: ECTPoint) {
            guard let doc = appState.selectedDocument else { return }
            var polys = doc.loadAllPolygons()
            if polys.isEmpty { return }

            for i in 0..<polys.count {
                let sp = polys[i]
                if FillAlgorithms.isPointInPolygon(
                    pixel,
                    polygon: sp.points,
                    fillRule: appState.fillRule
                ) {
                    polys.remove(at: i)
                    doc.saveAllPolygons(polys)

                    mainRenderer?.clearPolygons()
                    reloadPolygonsFromDoc()
                    return
                }
            }
        }

        /// Lasso clipping
        @MainActor private func performLassoClipping(_ lasso: [ECTPoint]) {
            guard let doc = appState.selectedDocument else { return }
            var polygons = doc.loadAllPolygons()
            if polygons.isEmpty { return }

            var newPolys: [StoredPolygon] = []
            for sp in polygons {
                let originalPoints = sp.points.map { ECTPoint(x: $0.x, y: $0.y) }
                let clippedPoints: [ECTPoint]
                switch appState.selectedPolygonAlgorithm {
                case .cyrusBeck:
                    clippedPoints = clipWithConcaveWindow(
                        subjectPolygon: originalPoints,
                        windowPolygon: lasso,
                        algo: .cyrusBeck
                    )
                case .sutherlandHodgman:
                    clippedPoints = clipWithConcaveWindow(
                        subjectPolygon: originalPoints,
                        windowPolygon: lasso,
                        algo: .sutherlandHodgman
                    )
                }
                if clippedPoints.count >= 3 {
                    let newPoly = StoredPolygon(
                        points: clippedPoints.map { Point2D(x: $0.x, y: $0.y) },
                        color: sp.color,
                        polygonTextureData: sp.polygonTextureData,
                        textureWidth: sp.textureWidth,
                        textureHeight: sp.textureHeight
                    )
                    newPolys.append(newPoly)
                } else {
                    newPolys.append(sp)
                }
            }
            doc.saveAllPolygons(newPolys)

            mainRenderer?.clearPolygons()
            reloadPolygonsFromDoc()
        }

        // MARK: - reloadPolygonsFromDoc

        /// Reloads all polygons from the current PicExpressDocument into the renderer.
        /// Clears the existing polygon list, then loads from doc.loadAllPolygons().
        /// If the document is in "multi-polygon" mode (mergedPolygons = true),
        /// we set `alreadyTriangulated = true` so we skip re-earclipping.
        @MainActor
        func reloadPolygonsFromDoc() {
            guard let mr = mainRenderer,
                  let doc = appState.selectedDocument
            else {
                return
            }

            // 1) clear the local array of polygons
            mr.clearPolygons()

            // 2) get all stored polygons from the doc
            let storedPolygons = doc.loadAllPolygons()

            // If doc.mergePolygons is true => indicates that doc is a single "multi-triangles" polygon
            let isAlreadyTriangulated = doc.mergePolygons

            for sp in storedPolygons {
                let ectPoints = sp.points.map { ECTPoint(x: $0.x, y: $0.y) }
                let c = SIMD4<Float>(sp.color[0], sp.color[1], sp.color[2], sp.color[3])

                // 3) call addPolygon with `alreadyTriangulated = isAlreadyTriangulated`
                mr.polygonRenderer.addPolygon(
                    points: ectPoints,
                    color: c,
                    alreadyTriangulated: isAlreadyTriangulated
                )

                // 4) if there's a polygonTextureData => load it as an MTLTexture
                if let texData = sp.polygonTextureData,
                   let w = sp.textureWidth,
                   let h = sp.textureHeight,
                   let newTex = mr.device.makeTexture(descriptor: {
                       let desc = MTLTextureDescriptor()
                       desc.pixelFormat = .rgba8Unorm
                       desc.width = w
                       desc.height = h
                       desc.usage = [.shaderRead]
                       desc.storageMode = .managed
                       return desc
                   }())
                {
                    texData.withUnsafeBytes { rawBuf in
                        newTex.replace(
                            region: MTLRegionMake2D(0, 0, w, h),
                            mipmapLevel: 0,
                            withBytes: rawBuf.baseAddress!,
                            bytesPerRow: w*4
                        )
                    }

                    // we retrieve the last polygon in polygonRenderer
                    if let lastIndex = mr.polygonRenderer.polygons.indices.last {
                        var polyData = mr.polygonRenderer.polygons[lastIndex]
                        polyData.texture = newTex
                        polyData.usesTexture = true
                        mr.polygonRenderer.polygons[lastIndex] = polyData
                    }
                }
            }

            // 5) ask for a redraw
            metalView?.needsDisplay = true
        }

        // MARK: - boundingBox

        /// Returns (minX, minY, maxX, maxY) for the polygon
        private func boundingBox(_ pts: [Point2D]) -> (Double, Double, Double, Double) {
            var minX = Double.greatestFiniteMagnitude
            var maxX = -Double.greatestFiniteMagnitude
            var minY = Double.greatestFiniteMagnitude
            var maxY = -Double.greatestFiniteMagnitude

            for p in pts {
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
            }
            return (minX, minY, maxX, maxY)
        }

        // MARK: - polygonsOverlap

        /**
         Checks if two polygons are "overlapping" or at least "touching" by edges or corners.
         1) bounding-box check
         2) if bounding boxes do not overlap/touch => false
         3) we do a sutherlandHodgmanClip => if >=3 points => there's a real intersect area => true
         4) else we check edges or corners adjacency => if they share at least an edge or corner => true
         */
        private func polygonsOverlap(_ spA: StoredPolygon, _ spB: StoredPolygon) -> Bool {
            // 1) bounding box
            let bbA = boundingBox(spA.points)
            let bbB = boundingBox(spB.points)
            if !boundingBoxesTouchOrOverlap(bbA, bbB) {
                return false
            }

            // 2) polygon intersection
            let ptsA = spA.points.map { ECTPoint(x: $0.x, y: $0.y) }
            let ptsB = spB.points.map { ECTPoint(x: $0.x, y: $0.y) }
            let inter = sutherlandHodgmanClip(subjectPolygon: ptsA, clipWindow: ptsB)
            if inter.count >= 3 {
                return true
            }

            // 3) check edges/corners
            if edgesOrCornersTouch(ptsA, ptsB) {
                return true
            }

            return false
        }

        /// boundingBoxesTouchOrOverlap => returns true if bounding boxes at least intersect or share an edge/corner.
        private func boundingBoxesTouchOrOverlap(
            _ bbA: (Double, Double, Double, Double),
            _ bbB: (Double, Double, Double, Double)
        ) -> Bool {
            let (aMinX, aMinY, aMaxX, aMaxY) = bbA
            let (bMinX, bMinY, bMaxX, bMaxY) = bbB

            if aMaxX < bMinX { return false }
            if aMinX > bMaxX { return false }
            if aMaxY < bMinY { return false }
            if aMinY > bMaxY { return false }
            return true
        }

        private func edgesOrCornersTouch(_ ptsA: [ECTPoint], _ ptsB: [ECTPoint]) -> Bool {
            // 1) corner check
            let setB = Set(ptsB)
            for pA in ptsA {
                if setB.contains(pA) {
                    return true
                }
            }

            // 2) edge intersection
            for i in 0..<ptsA.count {
                let j = (i + 1) % ptsA.count
                let segA1 = ptsA[i]
                let segA2 = ptsA[j]

                for k in 0..<ptsB.count {
                    let l = (k + 1) % ptsB.count
                    let segB1 = ptsB[k]
                    let segB2 = ptsB[l]
                    if segmentsIntersect(segA1, segA2, segB1, segB2) {
                        return true
                    }
                }
            }
            return false
        }

        private func segmentsIntersect(_ p1: ECTPoint, _ p2: ECTPoint,
                                       _ p3: ECTPoint, _ p4: ECTPoint) -> Bool
        {
            if !segmentBoundingBoxesTouch(p1, p2, p3, p4) {
                return false
            }

            let o1 = orientation(p1, p2, p3)
            let o2 = orientation(p1, p2, p4)
            let o3 = orientation(p3, p4, p1)
            let o4 = orientation(p3, p4, p2)

            if o1 != o2 && o3 != o4 { return true }
            if o1 == 0 && onSegment(p1, p3, p2) { return true }
            if o2 == 0 && onSegment(p1, p4, p2) { return true }
            if o3 == 0 && onSegment(p3, p1, p4) { return true }
            if o4 == 0 && onSegment(p3, p2, p4) { return true }

            return false
        }

        private func segmentBoundingBoxesTouch(_ p1: ECTPoint, _ p2: ECTPoint,
                                               _ p3: ECTPoint, _ p4: ECTPoint) -> Bool
        {
            let minX1 = min(p1.x, p2.x)
            let maxX1 = max(p1.x, p2.x)
            let minY1 = min(p1.y, p2.y)
            let maxY1 = max(p1.y, p2.y)

            let minX2 = min(p3.x, p4.x)
            let maxX2 = max(p3.x, p4.x)
            let minY2 = min(p3.y, p4.y)
            let maxY2 = max(p3.y, p4.y)

            if maxX1 < minX2 { return false }
            if minX1 > maxX2 { return false }
            if maxY1 < minY2 { return false }
            if minY1 > maxY2 { return false }

            return true
        }

        private func orientation(_ a: ECTPoint, _ b: ECTPoint, _ c: ECTPoint) -> Int {
            let val = (b.y - a.y)*(c.x - b.x) - (b.x - a.x)*(c.y - b.y)
            if abs(val) < 1e-12 { return 0 }
            return (val > 0) ? 1 : 2
        }

        private func onSegment(_ q: ECTPoint, _ p: ECTPoint, _ r: ECTPoint) -> Bool {
            if p.x >= min(q.x, r.x) && p.x <= max(q.x, r.x)
                && p.y >= min(q.y, r.y) && p.y <= max(q.y, r.y)
            {
                return true
            }
            return false
        }

        // MARK: - Helpers

        func screenPointToPixel(_ pt: CGPoint, in view: NSView, docWidth: Int, docHeight: Int) -> ECTPoint {
            let size = view.bounds.size
            if size.width <= 0 || size.height <= 0 {
                return ECTPoint(x: 0, y: 0)
            }
            let nx = pt.x / size.width
            let ny = pt.y / size.height
            let px = Double(nx)*Double(docWidth)
            let py = Double(ny)*Double(docHeight)
            return ECTPoint(x: px, y: py)
        }

        private func createShapePolygon(
            _ shapeType: ShapeType,
            start: ECTPoint,
            end: ECTPoint
        ) -> [ECTPoint] {
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
                let sX = (start.x < end.x) ? start.x : end.x
                let sY = (start.y < end.y) ? start.y : end.y
                return [
                    ECTPoint(x: sX, y: sY),
                    ECTPoint(x: sX + side, y: sY),
                    ECTPoint(x: sX + side, y: sY + side),
                    ECTPoint(x: sX, y: sY + side)
                ]
            case .circle:
                let rx = (maxX - minX)*0.5
                let ry = (maxY - minY)*0.5
                let cx = (maxX + minX)*0.5
                let cy = (maxY + minY)*0.5
                let r = min(rx, ry)
                return approximateEllipse(center: ECTPoint(x: cx, y: cy), rx: r, ry: r, segments: 32)
            case .ellipse:
                let cx = (maxX + minX)*0.5
                let cy = (maxY + minY)*0.5
                let rx = (maxX - minX)*0.5
                let ry = (maxY - minY)*0.5
                return approximateEllipse(center: ECTPoint(x: cx, y: cy), rx: rx, ry: ry, segments: 32)
            case .triangle:
                let midX = (minX + maxX)*0.5
                return [
                    ECTPoint(x: midX, y: maxY),
                    ECTPoint(x: minX, y: minY),
                    ECTPoint(x: maxX, y: minY)
                ]
            }
        }

        private func approximateEllipse(
            center: ECTPoint,
            rx: Double,
            ry: Double,
            segments: Int
        ) -> [ECTPoint] {
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

        func handleScrollWheel(_ event: NSEvent) {}

        // MARK: - BFS to find connected polygons

        /// findConnectedPolygonsIndices: returns all polygons (indices) that share the same color as
        /// polygons[startIndex], and are directly or indirectly overlapping with it.
        private func findConnectedPolygonsIndices(
            polygons: [StoredPolygon],
            startIndex: Int
        ) -> [Int] {
            // The color of the clicked polygon
            let oldColor = polygons[startIndex].color

            // Gather all polygons that share the same oldColor
            let sameColorIndices = polygons.indices.filter { polygons[$0].color == oldColor }

            var visited = Set<Int>()
            var queue = [startIndex]

            while !queue.isEmpty {
                let current = queue.removeFirst()
                if visited.contains(current) {
                    continue
                }
                visited.insert(current)

                for other in sameColorIndices {
                    if !visited.contains(other) {
                        // If the polygons overlap/touch => add to queue
                        if polygonsOverlap(polygons[current], polygons[other]) {
                            queue.append(other)
                        }
                    }
                }
            }

            return Array(visited)
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
            if event.keyCode == 36 { // Enter
                coordinator?.keyPressedEnter()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
