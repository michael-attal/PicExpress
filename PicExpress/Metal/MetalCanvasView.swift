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

    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoom: $zoom,
            panOffset: $panOffset,
            appState: appState
        )
    }

    func makeNSView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported.")
        }

        let mtkView = ZoomableMTKView(frame: .zero, device: device)
        mtkView.framebufferOnly = false
        mtkView.sampleCount = 4

        // Create the main renderer
        let mr = MainMetalRenderer(
            mtkView: mtkView,
            width: appState.selectedDocument?.width ?? 512,
            height: appState.selectedDocument?.height ?? 512
        )
        mr.appState = appState
        mtkView.delegate = mr

        // Store references
        context.coordinator.metalView = mtkView
        context.coordinator.mainRenderer = mr
        mtkView.coordinator = context.coordinator

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

                self.zoom = 1.0 // bestFitZoom
                self.panOffset = .zero

                mr.setZoomAndPan(zoom: self.zoom, panOffset: self.panOffset)
            }
        }

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

        private var isShapeDrawing = false

        /// Starting cords for .shapes tool
        private var shapeStartDocCoords = SIMD2<Float>(0, 0)

        /// Preview points for current shape
        private var shapePreviewPoints: [ECTPoint] = []

        private var isResizing = false
        private var draggedVertexForIndexResize: Int? = nil
        private var draggedIndicesForResize: [Int] = []

        private var isMoving = false
        private var draggedIndicesForMove: [Int] = []

        private var originalPositions: [SIMD2<Float>] = []
        private var startX: Float = 0
        private var startY: Float = 0

        private let vertexPickThreshold: Float = 10.0

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
            let maxZoom = min(ratioW, ratioH)*8.0

            let minZoom: CGFloat = 0.8
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
            let minVal = (half - 1.0) / 2.0
            let maxVal = (1.0 - half) / 2.0
            // Possibly minVal > maxVal if s>1 => reorder them
            let rmin = min(minVal, maxVal)
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
                let factor = 1+sender.magnification
                sender.magnification = 0

                // Multiply current zoom
                var newZoom = zoom*factor
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
                zoom = clampZoom(to: oldZoom*zoomFactor)
            } else if event.deltaY < 0 {
                // scroll down => zoom out
                zoom = clampZoom(to: oldZoom / zoomFactor)
            }

            // clamp pan again
            panOffset = clampPanOffset(panOffset, zoom: zoom)

            mainRenderer?.setZoomAndPan(zoom: zoom, panOffset: panOffset)
        }

        // MARK: - Mouse & keyboard

        func convertClickToDocumentCoords(
            pt: NSPoint,
            view: NSView,
            renderer: MainMetalRenderer,
            document: PicExpressDocument
        ) -> (Float, Float)? {
            let viewSize = view.bounds.size
            if viewSize.width <= 0 || viewSize.height <= 0 { return nil }

            let ndcX = Float((pt.x / viewSize.width)*2.0 - 1.0)
            let ndcY = Float((pt.y / viewSize.height)*2.0 - 1.0)
            let ndcPos = simd_float4(ndcX, ndcY, 0, 1)

            let invTransform = simd_inverse(renderer.currentTransform)
            let docNdcPos = invTransform*ndcPos

            let docW = Float(document.width)
            let docH = Float(document.height)

            let docNdcX = docNdcPos.x / docNdcPos.w
            let docNdcY = docNdcPos.y / docNdcPos.w

            let px = (docNdcX+1)*0.5*docW
            let py = (docNdcY+1)*0.5*docH

            print("""
            [mouseClicked - convertClickToDocumentCoords] 
              - view coords = (\(pt.x), \(pt.y))
              - ndc = (\(ndcX), \(ndcY))
              - docNdc = (\(docNdcX), \(docNdcY))
              - doc coords float = (\(px), \(py))
            """)

            return (px, py)
        }

        func mouseClicked(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            guard let mr = mainRenderer else { return }
            guard let doc = appState.selectedDocument else { return }

            switch tool {
            case .addPolygonFromClick:
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    print("In addPolygonFromClick tool, clicked at (\(px), \(py))")
                    let newPoint = ECTPoint(x: Double(px), y: Double(py))
                    appState.lassoPoints.append(newPoint)
                    mr.updatePreviewPoints(appState.lassoPoints)
                }

            case .cut:
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    print("CUT: we add a cutting point at (\(px), \(py))")
                    let newPoint = ECTPoint(x: Double(px), y: Double(py))
                    appState.lassoPoints.append(newPoint)
                    mr.updatePreviewPoints(appState.lassoPoints)
                }

            case .resize:
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    pickNearestVertexOrNone(x: px, y: py)
                }

            case .movePolygon:
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    pickVerticesForMovePolygon(x: px, y: py)
                }

            case .fill:
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    print("In fill tool, clicked at (\(px), \(py))")
                    handleFillClick(px: px, py: py, renderer: mr)
                }

            case .shapes:
                // We start the drawing of the shape
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    print("In shapes tool, clicked at (\(px), \(py))")
                    shapeStartDocCoords = SIMD2<Float>(px, py)
                    isShapeDrawing = true
                    shapePreviewPoints.removeAll()
                    mr.updatePreviewPoints([])
                }

            case .eraser:
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    handleEraserClick(px: px, py: py, renderer: mr)
                }

            default:
                break
            }
        }

        func mouseDragged(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            guard let mr = mainRenderer else { return }
            guard let doc = appState.selectedDocument else { return }

            switch tool {
            case .shapes:
                guard isShapeDrawing else { return }
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    if let shapeType = appState.currentShapeType {
                        let points = buildShapePoints(shapeType: shapeType,
                                                      start: shapeStartDocCoords,
                                                      end: SIMD2<Float>(px, py))
                        shapePreviewPoints = points
                        mr.updatePreviewPoints(shapePreviewPoints)
                    }
                }
            case .resize:
                guard isResizing else { return }
                if draggedIndicesForResize.isEmpty { return }

                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    // Calculate delta
                    let dx = px - startX
                    let dy = py - startY

                    // Apply this delta to all selected vertices
                    for i in 0..<draggedIndicesForResize.count {
                        let idx = draggedIndicesForResize[i]
                        let origPos = originalPositions[i]
                        mr.lastVertices[idx].position = SIMD2<Float>(
                            origPos.x+dx,
                            origPos.y+dy
                        )
                    }

                    let updatedVerts = mr.lastVertices
                    let updatedIndices = mr.lastIndices
                    mr.meshRenderer.updateMesh(vertices: updatedVerts, indices: updatedIndices)

                    rebuildFillCPUAndUpdateTexture(verts: updatedVerts, indices: updatedIndices)
                }
            case .movePolygon:
                guard isMoving, !draggedIndicesForMove.isEmpty else { return }
                if let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) {
                    // 1)Update vertex position
                    let dx = px - startX
                    let dy = py - startY

                    for i in 0..<draggedIndicesForMove.count {
                        let idx = draggedIndicesForMove[i]
                        let origPos = originalPositions[i]
                        mr.lastVertices[idx].position = SIMD2<Float>(
                            origPos.x+dx,
                            origPos.y+dy
                        )
                    }

                    // 2) Update GPU mesh
                    let updatedVerts = mr.lastVertices
                    let updatedIndices = mr.lastIndices
                    mr.meshRenderer.updateMesh(vertices: updatedVerts, indices: updatedIndices)

                    // 3) Re-build CPU fill => “live preview”.
                    rebuildFillCPUAndUpdateTexture(verts: updatedVerts, indices: updatedIndices)
                }
            default:
                break
            }
        }

        func mouseUp(at pt: NSPoint, in view: NSView) {
            guard let tool = appState.selectedTool else { return }
            guard let mr = mainRenderer else { return }
            guard let doc = appState.selectedDocument else { return }

            switch tool {
            case .addPolygonFromClick:
                break

            case .cut:
                break

            case .shapes:
                if isShapeDrawing {
                    isShapeDrawing = false

                    let finalPoints = shapePreviewPoints
                    shapePreviewPoints.removeAll()
                    mr.updatePreviewPoints([])

                    guard finalPoints.count >= 3 else {
                        return
                    }
                    // We finalize => triangulation + insertion in the mesh
                    finalizePolygon(finalPoints, color: appState.selectedColor)
                }

            case .resize:
                if isResizing {
                    isResizing = false

                    let updatedVerts = mr.lastVertices
                    let updatedIndices = mr.lastIndices
                    doc.saveMesh(updatedVerts, updatedIndices)

                    doc.saveFillTexture(mr.cpuBuffer, width: mr.texWidth, height: mr.texHeight)

                    draggedVertexForIndexResize = nil
                    draggedIndicesForResize.removeAll()
                    originalPositions.removeAll()

                    print("Resize terminé => mesh + texture sauvegardés.")
                }

            case .movePolygon:
                if isMoving, !draggedIndicesForMove.isEmpty {
                    isMoving = false

                    let updatedVerts = mr.lastVertices
                    let updatedIndices = mr.lastIndices

                    doc.saveMesh(updatedVerts, updatedIndices)
                    doc.saveFillTexture(mr.cpuBuffer, width: mr.texWidth, height: mr.texHeight)

                    draggedIndicesForMove.removeAll()
                    originalPositions.removeAll()

                    print("Resize finalized => mesh + texture saved.")
                }

            default:
                break
            }
        }

        func keyPressedEnter() {
            guard let tool = appState.selectedTool else { return }
            switch tool {
            case .addPolygonFromClick:
                if appState.lassoPoints.count >= 3 {
                    finalizePolygon(appState.lassoPoints, color: appState.selectedColor)
                }
                appState.lassoPoints.removeAll()
                mainRenderer?.updatePreviewPoints([])

            case .cut:
                // The user has just placed appstate.lassoPoints to define the polynomial window
                guard let mr = mainRenderer else { return }
                guard let doc = appState.selectedDocument else { return }

                if appState.lassoPoints.count >= 3 {
                    // 1) Convert lassoPoints (ECTpoint/Double) to [SIMD2<Float>] (Pixel coords)
                    let clipWindow: [SIMD2<Float>] = appState.lassoPoints.map {
                        SIMD2<Float>(Float($0.x), Float($0.y))
                    }

                    // 2) Load the old mesh from the document
                    guard let (oldVerts, oldIndices) = doc.loadMesh() else {
                        print("No mesh in the doc => no cutting.")
                        appState.lassoPoints.removeAll()
                        mr.updatePreviewPoints([])
                        return
                    }

                    // 3) Browse each triangle of the old mesh
                    var newVertices: [PolygonVertex] = []
                    var newIndices: [UInt16] = []
                    var currentIndex: UInt16 = 0

                    let countTris = oldIndices.count / 3
                    for t in 0..<countTris {
                        let iA = oldIndices[3*t+0]
                        let iB = oldIndices[3*t+1]
                        let iC = oldIndices[3*t+2]
                        let A = oldVerts[Int(iA)]
                        let B = oldVerts[Int(iB)]
                        let C = oldVerts[Int(iC)]
                        let triPoly = [A.position, B.position, C.position]

                        let clippedPoly: [SIMD2<Float>]
                        switch appState.selectedClippingAlgorithm {
                        case .cyrusBeck:
                            clippedPoly = ClippingAlgorithms.cyrusBeckClip(subjectPolygon: triPoly, clipWindow: clipWindow)
                        case .sutherlandHodgman:
                            clippedPoly = ClippingAlgorithms.sutherlandHodgmanClip(subjectPolygon: triPoly, clipWindow: clipWindow)
                        }

                        if clippedPoly.count < 3 { continue }

                        let ectPoly = ECTPolygon(vertices: clippedPoly.map {
                            ECTPoint(x: Double($0.x), y: Double($0.y))
                        })
                        let triList = EarClippingTriangulation().getEarClipTriangles(polygon: ectPoly)

                        // 6) For each triangle produced, 3 new PolygonVertex is created
                        // Keep the same color as the vertice A
                        let colorA = A.color
                        let polyIDs = A.polygonIDs // Keep the ID to find out which original poly it comes

                        for tri in triList {
                            // Convert ECTPoint -> SIMD2<Float>
                            let pA = SIMD2<Float>(Float(tri.a.x), Float(tri.a.y))
                            let pB = SIMD2<Float>(Float(tri.b.x), Float(tri.b.y))
                            let pC = SIMD2<Float>(Float(tri.c.x), Float(tri.c.y))

                            let iA2 = currentIndex
                            let iB2 = currentIndex+1
                            let iC2 = currentIndex+2
                            currentIndex += 3

                            newIndices.append(iA2)
                            newIndices.append(iB2)
                            newIndices.append(iC2)

                            newVertices.append(PolygonVertex(position: pA,
                                                             uv: .zero,
                                                             color: colorA,
                                                             polygonIDs: polyIDs))
                            newVertices.append(PolygonVertex(position: pB,
                                                             uv: .zero,
                                                             color: colorA,
                                                             polygonIDs: polyIDs))
                            newVertices.append(PolygonVertex(position: pC,
                                                             uv: .zero,
                                                             color: colorA,
                                                             polygonIDs: polyIDs))
                        }
                    }

                    // 7) Save this new mesh in the document
                    doc.saveMesh(newVertices, newIndices)

                    // 8) Update the rendering (Mesh GPU)
                    mr.meshRenderer.updateMesh(vertices: newVertices, indices: newIndices)

                    // Refill entire CPU texture
                    if let fillTex = mr.fillTexture {
                        // a) We first empty the CPU Buffer
                        let w = mr.texWidth
                        let h = mr.texHeight
                        var cpuBuf = [UInt8](repeating: 0, count: w*h*4)
                        for i in 0..<(w*h) {
                            let idx = i*4
                            cpuBuf[idx+0] = 0
                            cpuBuf[idx+1] = 0
                            cpuBuf[idx+2] = 0
                            cpuBuf[idx+3] = 255
                        }
                        // b) We are it on the triangles of the new mesh => we apply LCA
                        let triCount2 = newIndices.count / 3
                        for t2 in 0..<triCount2 {
                            let iA2 = newIndices[3*t2+0]
                            let iB2 = newIndices[3*t2+1]
                            let iC2 = newIndices[3*t2+2]
                            let A2 = newVertices[Int(iA2)]
                            let B2 = newVertices[Int(iB2)]
                            let C2 = newVertices[Int(iC2)]
                            let triPoly2: [SIMD2<Float>] = [A2.position, B2.position, C2.position]
                            // Color => We take the color of A2
                            let col = A2.color
                            let fillColor = (
                                UInt8(255*col.x),
                                UInt8(255*col.y),
                                UInt8(255*col.z),
                                UInt8(255*col.w)
                            )
                            // c) LCA on this triangle
                            FillAlgorithms.fillPolygonLCA(
                                polygon: triPoly2,
                                pixels: &cpuBuf,
                                width: w,
                                height: h,
                                fillColor: fillColor,
                                fillRule: .evenOdd
                            )
                        }

                        // d) Update the GPU texture
                        mr.updateFillTextureCPU(cpuBuf)

                        // e) Save in the doc
                        doc.saveFillTexture(cpuBuf, width: w, height: h)
                    }

                    print("Cutting finished, new updated mesh.")
                }

                // Whatever the result, we reset the lasso
                appState.lassoPoints.removeAll()
                mr.updatePreviewPoints([])

            default:
                break
            }
        }

        // MARK: - fill / erase / etc

        private func handleFillClick(px: Float, py: Float, renderer: MainMetalRenderer) {
            let ix = Int(px.rounded())
            let iy = Int(py.rounded())

            guard let (allVerts, allIndices) = renderer.exportCurrentMesh() else {
                print(">>> Warning: exportCurrentMesh return nil")
                return
            }
            let clickPos = SIMD2<Float>(px, py)

            var foundTri: (PolygonVertex, PolygonVertex, PolygonVertex)? = nil
            var n = allIndices.count
            var i = 0
            while i < n {
                let iA = allIndices[i]
                let iB = allIndices[i+1]
                let iC = allIndices[i+2]
                let A = allVerts[Int(iA)]
                let B = allVerts[Int(iB)]
                let C = allVerts[Int(iC)]
                if renderer.pointInTriangle(p: clickPos, a: A.position, b: B.position, c: C.position) {
                    print("FOUND triangle at indices \(iA),\(iB),\(iC)")
                    foundTri = (A, B, C)
                    break
                }
                i += 3
            }
            guard let (vA, vB, vC) = foundTri else {
                print("No triangle found under click => no fill done")
                return
            }

            let selectedFillColor = appState.selectedColor.toSIMD4()
            let fillColor = (
                UInt8(255*selectedFillColor.x),
                UInt8(255*selectedFillColor.y),
                UInt8(255*selectedFillColor.z),
                UInt8(255*selectedFillColor.w)
            )

            if appState.selectedFillAlgorithm == .lca {
                switch appState.selectedDetectionMode {
                case .triangle:
                    let triPoly = [vA.position, vB.position, vC.position]
                    renderer.applyFillAlgorithm(algo: .lca,
                                                polygon: triPoly,
                                                seed: nil,
                                                fillColor: fillColor,
                                                fillRule: appState.selectedFillRule)
                case .polygon:
                    let pid = vA.polygonIDs.x
                    if pid < 0 {
                        print("No valid polygonID => fill only the triangle.")
                        let triPoly = [vA.position, vB.position, vC.position]
                        renderer.applyFillAlgorithm(algo: .lca,
                                                    polygon: triPoly,
                                                    seed: nil,
                                                    fillColor: fillColor,
                                                    fillRule: appState.selectedFillRule)
                    } else {
                        var allPolygonsTris: [[SIMD2<Float>]] = []
                        i = 0
                        while i < n {
                            let iA = allIndices[i]
                            let iB = allIndices[i+1]
                            let iC = allIndices[i+2]
                            let A = allVerts[Int(iA)]
                            let B = allVerts[Int(iB)]
                            let C = allVerts[Int(iC)]
                            let matchA = (A.polygonIDs.x == pid
                                || A.polygonIDs.y == pid
                                || A.polygonIDs.z == pid
                                || A.polygonIDs.w == pid)
                            let matchB = (B.polygonIDs.x == pid
                                || B.polygonIDs.y == pid
                                || B.polygonIDs.z == pid
                                || B.polygonIDs.w == pid)
                            let matchC = (C.polygonIDs.x == pid
                                || C.polygonIDs.y == pid
                                || C.polygonIDs.z == pid
                                || C.polygonIDs.w == pid)
                            if matchA || matchB || matchC {
                                allPolygonsTris.append([A.position, B.position, C.position])
                            }
                            i += 3
                        }
                        // fill each
                        for tri in allPolygonsTris {
                            renderer.applyFillAlgorithm(algo: .lca,
                                                        polygon: tri,
                                                        seed: nil,
                                                        fillColor: fillColor,
                                                        fillRule: appState.selectedFillRule)
                        }
                    }
                }

            } else {
                // seed fill => (.seedRecursive, .seedStack, .scanline)
                renderer.applyFillAlgorithm(algo: appState.selectedFillAlgorithm,
                                            polygon: [],
                                            seed: (ix, iy),
                                            fillColor: fillColor,
                                            fillRule: appState.selectedFillRule)
            }
        }

        private func pickNearestVertexOrNone(x: Float, y: Float) {
            guard let mr = mainRenderer else { return }
            let allVerts = mr.lastVertices
            if allVerts.isEmpty { return }

            // 1) Find the nearest vertex index
            var closestIndex = -1
            var closestDist = Float.greatestFiniteMagnitude
            for (i, vtx) in allVerts.enumerated() {
                let dx = vtx.position.x - x
                let dy = vtx.position.y - y
                let dist = sqrtf(dx*dx+dy*dy)
                if dist < closestDist {
                    closestDist = dist
                    closestIndex = i
                }
            }

            // Distance threshold
            if closestIndex >= 0, closestDist < vertexPickThreshold {
                isResizing = true

                // 2) Retrieve the polygonIDs of the selected vertex
                let selectedVertex = allVerts[closestIndex]
                let selectedPos = selectedVertex.position

                // We'll create a Set for valid IDs
                var selectedIDs = Set<Int32>()
                // Ignore IDs < 0
                if selectedVertex.polygonIDs.x >= 0 { selectedIDs.insert(selectedVertex.polygonIDs.x) }
                if selectedVertex.polygonIDs.y >= 0 { selectedIDs.insert(selectedVertex.polygonIDs.y) }
                if selectedVertex.polygonIDs.z >= 0 { selectedIDs.insert(selectedVertex.polygonIDs.z) }
                if selectedVertex.polygonIDs.w >= 0 { selectedIDs.insert(selectedVertex.polygonIDs.w) }

                // 3) Traverse all vertices to find
                // those sharing ≥1 polygonID AND the same position
                let epsilon: Float = 1e-6
                var groupIndices: [Int] = []
                var groupOriginalPositions: [SIMD2<Float>] = []

                for (i, vtx) in allVerts.enumerated() {
                    // Check A: Intersection of at least one ID
                    let vIDs = [vtx.polygonIDs.x, vtx.polygonIDs.y,
                                vtx.polygonIDs.z, vtx.polygonIDs.w]
                    let hasCommonID = vIDs.contains(where: { $0 >= 0 && selectedIDs.contains($0) })
                    if !hasCommonID {
                        continue
                    }

                    // Check B: position almost identical to selected vertex?
                    let dx = vtx.position.x - selectedPos.x
                    let dy = vtx.position.y - selectedPos.y
                    let dist = sqrtf(dx*dx+dy*dy)
                    if dist < epsilon {
                        groupIndices.append(i)
                        groupOriginalPositions.append(vtx.position)
                    }
                }

                // We use draggedIndicesForResize to move the whole group
                draggedIndicesForResize = groupIndices
                originalPositions = groupOriginalPositions
                draggedVertexForIndexResize = nil

                // We record the click position to calculate a delta
                startX = x
                startY = y

                print("Resize => pick vertex #\(closestIndex) => groupe de \(groupIndices.count) sommets.")
            } else {
                // Rien de proche => annuler
                isResizing = false
                draggedVertexForIndexResize = nil
                draggedIndicesForResize.removeAll()
                originalPositions.removeAll()
            }
        }

        private func handleEraserClick(px: Float, py: Float, renderer: MainMetalRenderer) {
            let ix = Int(px.rounded())
            let iy = Int(py.rounded())

            // 1) Retrieve the current mesh
            guard let (allVerts, allIndices) = renderer.exportCurrentMesh() else {
                print("Eraser: no mesh => nothing to erase")
                return
            }

            // 2) Find which triangle is clicked
            let clickPos = SIMD2<Float>(px, py)
            var foundTriIndex: Int? = nil // index dans allIndices
            var foundTriVertices: (PolygonVertex, PolygonVertex, PolygonVertex)? = nil

            var i = 0
            while i < allIndices.count {
                let iA = allIndices[i]
                let iB = allIndices[i+1]
                let iC = allIndices[i+2]
                let A = allVerts[Int(iA)]
                let B = allVerts[Int(iB)]
                let C = allVerts[Int(iC)]

                if renderer.pointInTriangle(p: clickPos, a: A.position, b: B.position, c: C.position) {
                    foundTriIndex = i
                    foundTriVertices = (A, B, C)
                    break
                }
                i += 3
            }

            guard let triBaseIndex = foundTriIndex,
                  let (vA, vB, vC) = foundTriVertices
            else {
                print("Eraser: no triangle found under click => nothing to remove.")
                return
            }

            // 3) Depending on the deletion mode
            // - .triangle => delete ONLY this triangle from the mesh
            // - .polygon => delete ALL triangles with this triangle's polygonID
            let eraserMode = appState.selectedDetectionMode // .triangle or .polygon

            let oldVertices = allVerts
            let oldIndices = allIndices

            // Nouveau tableau "filtré"
            var newVertices: [PolygonVertex] = []
            var newIndices: [UInt16] = []

            switch eraserMode {
            case .triangle:
                // We'll rebuild the list of triangles, skipping only the one we've found.
                // triBaseIndex, triBaseIndex+1, triBaseIndex+2
                (newVertices, newIndices) = removeOneTriangle(
                    oldVertices: oldVertices,
                    oldIndices: oldIndices,
                    triangleBaseIndex: triBaseIndex
                )

            case .polygon:
                // The polygon ID is retrieved from vA, vB, vC. Assume we take vA.polygonIDs.x
                let polygonID = vA.polygonIDs.x
                if polygonID < 0 {
                    // no ID => just delete this triangle
                    (newVertices, newIndices) = removeOneTriangle(
                        oldVertices: oldVertices,
                        oldIndices: oldIndices,
                        triangleBaseIndex: triBaseIndex
                    )
                } else {
                    (newVertices, newIndices) = removePolygon(
                        oldVertices: oldVertices,
                        oldIndices: oldIndices,
                        polygonIDtoRemove: polygonID
                    )
                }
            }

            // 4) Saving the new mesh in the document
            guard let doc = appState.selectedDocument else { return }
            doc.saveMesh(newVertices, newIndices)

            // 5) GPU mesh update
            renderer.meshRenderer.updateMesh(vertices: newVertices, indices: newIndices)

            // 6) Rebuild the (emptied) cpuBuffer, then fill in for each remaining triangle
            let w = renderer.texWidth
            let h = renderer.texHeight

            // Empty the CPU buffer => all black (or transparent).
            var cpuBuf = [UInt8](repeating: 0, count: w*h*4)
            for i in 0..<(w*h) {
                cpuBuf[i*4+0] = 0
                cpuBuf[i*4+1] = 0
                cpuBuf[i*4+2] = 0
                cpuBuf[i*4+3] = 255
            }

            // Re-fill ALL remaining mesh faces
            let triCount = newIndices.count / 3
            var idx = 0
            for _ in 0..<triCount {
                let iA = newIndices[idx]
                let iB = newIndices[idx+1]
                let iC = newIndices[idx+2]
                idx += 3

                let A = newVertices[Int(iA)]
                let B = newVertices[Int(iB)]
                let C = newVertices[Int(iC)]

                let col = A.color
                let fillColor = (
                    UInt8(255*col.x),
                    UInt8(255*col.y),
                    UInt8(255*col.z),
                    UInt8(255*col.w)
                )

                let triPoly = [A.position, B.position, C.position]

                // Fill in via LCA
                FillAlgorithms.fillPolygonLCA(
                    polygon: triPoly,
                    pixels: &cpuBuf,
                    width: w,
                    height: h,
                    fillColor: fillColor,
                    fillRule: .evenOdd
                )
            }

            // 7) Update GPU texture + save
            renderer.updateFillTextureCPU(cpuBuf)
            doc.saveFillTexture(cpuBuf, width: w, height: h)

            print("Eraser: triangle/polygon removed from mesh & fill updated.")
        }

        /// Deletes the exact triangle at triBaseIndex (a multiple of 3).
        /// Does NOT remove orphan vertices. We simply skip this triple.
        func removeOneTriangle(
            oldVertices: [PolygonVertex],
            oldIndices: [UInt16],
            triangleBaseIndex: Int
        ) -> ([PolygonVertex], [UInt16]) {
            var newVerts = oldVertices // do not touch
            var newInds: [UInt16] = []

            var i = 0
            while i < oldIndices.count {
                if i == triangleBaseIndex {
                    // skip the 3 indices => i, i+1, i+2
                    i += 3
                    continue
                }
                newInds.append(oldIndices[i])
                i += 1
            }

            return (newVerts, newInds)
        }

        func removePolygon(
            oldVertices: [PolygonVertex],
            oldIndices: [UInt16],
            polygonIDtoRemove: Int32
        ) -> ([PolygonVertex], [UInt16]) {
            var newVerts = oldVertices
            var newInds: [UInt16] = []

            var i = 0
            while i < oldIndices.count {
                let iA = oldIndices[i]
                let iB = oldIndices[i+1]
                let iC = oldIndices[i+2]

                let A = oldVertices[Int(iA)]
                let B = oldVertices[Int(iB)]
                let C = oldVertices[Int(iC)]

                let matchA = A.polygonIDs.contains(polygonIDtoRemove)
                let matchB = B.polygonIDs.contains(polygonIDtoRemove)
                let matchC = C.polygonIDs.contains(polygonIDtoRemove)

                if matchA || matchB || matchC {
                    // => this triangle belongs to the polygon => skip it
                    i += 3
                    continue
                } else {
                    newInds.append(iA)
                    newInds.append(iB)
                    newInds.append(iC)
                    i += 3
                }
            }

            return (newVerts, newInds)
        }

        private func pickVerticesForMovePolygon(x: Float, y: Float) {
            guard let mr = mainRenderer else { return }
            guard let (allVerts, allIndices) = mr.exportCurrentMesh() else {
                isMoving = false
                return
            }

            let clickPos = SIMD2<Float>(x, y)
            var foundTriBase: Int? = nil
            var triVertices: (PolygonVertex, PolygonVertex, PolygonVertex)? = nil

            var i = 0
            while i < allIndices.count {
                let iA = allIndices[i]
                let iB = allIndices[i+1]
                let iC = allIndices[i+2]
                let A = allVerts[Int(iA)]
                let B = allVerts[Int(iB)]
                let C = allVerts[Int(iC)]

                if mr.pointInTriangle(p: clickPos, a: A.position, b: B.position, c: C.position) {
                    foundTriBase = i
                    triVertices = (A, B, C)
                    break
                }
                i += 3
            }

            if foundTriBase == nil {
                print("Resize => no triangle under click => do nothing")
                isResizing = false
                draggedIndicesForMove.removeAll()
                originalPositions.removeAll()
                return
            }

            let triBase = foundTriBase!
            let iA = allIndices[triBase]
            let iB = allIndices[triBase+1]
            let iC = allIndices[triBase+2]
            let (vA, vB, vC) = triVertices!

            startX = x
            startY = y

            draggedIndicesForMove.removeAll()
            originalPositions.removeAll()

            switch appState.selectedDetectionMode {
            case .triangle:
                draggedIndicesForMove = [Int(iA), Int(iB), Int(iC)]
                for idx in draggedIndicesForMove {
                    originalPositions.append(allVerts[idx].position)
                }

            case .polygon:
                let pid = vA.polygonIDs.x
                if pid < 0 {
                    draggedIndicesForMove = [Int(iA), Int(iB), Int(iC)]
                    for idx in draggedIndicesForMove {
                        originalPositions.append(allVerts[idx].position)
                    }
                } else {
                    var list: [Int] = []
                    var listPos: [SIMD2<Float>] = []
                    for (idx, vv) in allVerts.enumerated() {
                        if vv.polygonIDs.contains(pid) {
                            list.append(idx)
                            listPos.append(vv.position)
                        }
                    }
                    draggedIndicesForMove = list
                    originalPositions = listPos
                }
            }

            isMoving = !draggedIndicesForMove.isEmpty
            print("pickVerticesForResizing => draggedIndices=\(draggedIndicesForMove), isResizing=\(isMoving)")
        }

        private func finalizePolygon(_ ectPoints: [ECTPoint], color: Color) {
            guard let doc = appState.selectedDocument else { return }
            guard let mr = mainRenderer else { return }

            let oldMesh = doc.loadMesh()
            var oldVertices: [PolygonVertex] = []
            var oldIndices: [UInt16] = []
            if let (ov, oi) = oldMesh {
                oldVertices = ov
                oldIndices = oi
            }

            let polyID = appState.nextPolygonID
            appState.nextPolygonID += 1

            let (newVertices, newIndices) = EarClippingTriangulation.earClipOnePolygon(
                ectPoints: ectPoints,
                color: color,
                existingVertexCount: oldVertices.count,
                polygonID: polyID
            )

            // 3) Merge
            let mergedVertices = oldVertices+newVertices
            let mergedIndices = oldIndices+newIndices

            // 4) Save doc
            doc.saveMesh(mergedVertices, mergedIndices)

            // 5) Update renderer
            mr.meshRenderer.updateMesh(vertices: mergedVertices, indices: mergedIndices)

            // 6) Fill auto
            let fillC = color.toSIMD4()
            let fillBytes = (
                UInt8(255*fillC.x),
                UInt8(255*fillC.y),
                UInt8(255*fillC.z),
                UInt8(255*fillC.w)
            )
            let polyFloat: [SIMD2<Float>] = ectPoints.map {
                SIMD2<Float>(Float($0.x), Float($0.y))
            }

            mr.applyFillAlgorithm(
                algo: .lca,
                polygon: polyFloat,
                seed: nil,
                fillColor: fillBytes,
                fillRule: .evenOdd
            )
        }

        // TODO: Refactor others tool to use this method to update buffers
        private func rebuildFillCPUAndUpdateTexture(verts: [PolygonVertex], indices: [UInt16]) {
            guard let mr = mainRenderer else { return }
            let w = mr.texWidth
            let h = mr.texHeight
            var cpuBuf = [UInt8](repeating: 0, count: w*h*4)
            for i in 0..<(w*h) {
                let idx = i*4
                cpuBuf[idx+0] = 0
                cpuBuf[idx+1] = 0
                cpuBuf[idx+2] = 0
                cpuBuf[idx+3] = 255
            }
            let triCount = indices.count / 3
            var idx = 0
            for _ in 0..<triCount {
                let iA = indices[idx]
                let iB = indices[idx+1]
                let iC = indices[idx+2]
                idx += 3

                let A = verts[Int(iA)]
                let B = verts[Int(iB)]
                let C = verts[Int(iC)]

                let col = A.color
                let fillColor = (
                    UInt8(255*col.x),
                    UInt8(255*col.y),
                    UInt8(255*col.z),
                    UInt8(255*col.w)
                )

                let triPoly = [A.position, B.position, C.position]

                FillAlgorithms.fillPolygonLCA(
                    polygon: triPoly,
                    pixels: &cpuBuf,
                    width: w,
                    height: h,
                    fillColor: fillColor,
                    fillRule: .evenOdd
                )
            }
            mr.updateFillTextureCPU(cpuBuf)

            //  Store in the coord. You don't necessarily save to the doc,
            // because we may want to do it in mouseUp mode. You can just assign a local "cpuBuffer" to the mr.
            mr.cpuBuffer = cpuBuf
        }

        private func buildShapePoints(shapeType: ShapeType,
                                      start: SIMD2<Float>,
                                      end: SIMD2<Float>) -> [ECTPoint]
        {
            let sx = Double(start.x)
            let sy = Double(start.y)
            let ex = Double(end.x)
            let ey = Double(end.y)

            switch shapeType {
            case .rectangle:
                return [
                    ECTPoint(x: sx, y: sy),
                    ECTPoint(x: sx, y: ey),
                    ECTPoint(x: ex, y: ey),
                    ECTPoint(x: ex, y: sy)
                ]

            case .square:
                let width = ex - sx
                let height = ey - sy
                let side = min(abs(width), abs(height))
                let signX = (width < 0) ? -1.0 : 1.0
                let signY = (height < 0) ? -1.0 : 1.0
                let ex2 = sx+side*signX
                let ey2 = sy+side*signY
                return [
                    ECTPoint(x: sx, y: sy),
                    ECTPoint(x: sx, y: ey2),
                    ECTPoint(x: ex2, y: ey2),
                    ECTPoint(x: ex2, y: sy)
                ]

            case .circle:
                let cx = (sx+ex)*0.5
                let cy = (sy+ey)*0.5
                let rx = abs(ex - sx)*0.5
                let ry = abs(ey - sy)*0.5
                let r = min(rx, ry)
                return approximateEllipse(cx: cx, cy: cy, rx: r, ry: r, segments: 64)

            case .ellipse:
                let cx = (sx+ex)*0.5
                let cy = (sy+ey)*0.5
                let rx = abs(ex - sx)*0.5
                let ry = abs(ey - sy)*0.5
                return approximateEllipse(cx: cx, cy: cy, rx: rx, ry: ry, segments: 64)

            case .triangle:
                let xmin = min(sx, ex)
                let xmax = max(sx, ex)
                let ymin = min(sy, ey)
                let ymax = max(sy, ey)
                let midX = (xmin+xmax)*0.5
                return [
                    ECTPoint(x: xmin, y: ymin),
                    ECTPoint(x: xmax, y: ymin),
                    ECTPoint(x: midX, y: ymax)
                ]
            }
        }

        private func approximateEllipse(cx: Double,
                                        cy: Double,
                                        rx: Double,
                                        ry: Double,
                                        segments: Int) -> [ECTPoint]
        {
            var pts: [ECTPoint] = []
            pts.reserveCapacity(segments)
            for i in 0..<segments {
                let theta = 2.0*Double.pi*Double(i) / Double(segments)
                let x = cx+rx*cos(theta)
                let y = cy+ry*sin(theta)
                pts.append(ECTPoint(x: x, y: y))
            }
            return pts
        }
    }

    // MARK: - ZoomableMTKView

    class ZoomableMTKView: MTKView {
        weak var coordinator: Coordinator?

        override func scrollWheel(with event: NSEvent) {
            coordinator?.handleScrollWheel(event)
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
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
