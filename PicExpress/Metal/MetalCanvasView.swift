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

                self.zoom = bestFitZoom
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

        // MARK: - Mouse & keyboard

        func convertClickToDocumentCoords(pt: NSPoint, view: NSView, renderer: MainMetalRenderer, document: PicExpressDocument) -> (Float, Float)? {
            let viewSize = view.bounds.size
            if viewSize.width <= 0 || viewSize.height <= 0 { return nil }

            let ndcX = Float((pt.x / viewSize.width) * 2.0 - 1.0)
            let ndcY = Float((pt.y / viewSize.height) * 2.0 - 1.0)
            let ndcPos = simd_float4(ndcX, ndcY, 0, 1)

            let invTransform = simd_inverse(renderer.currentTransform)
            let docNdcPos = invTransform * ndcPos

            let docW = Float(document.width)
            let docH = Float(document.height)

            let docNdcX = docNdcPos.x / docNdcPos.w
            let docNdcY = docNdcPos.y / docNdcPos.w

            let px = (docNdcX + 1) * 0.5 * docW
            let py = (docNdcY + 1) * 0.5 * docH

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
                guard let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) else { return }

                print("In addPolygonFromClick tool, clicked at (\(px), \(py))")

                let newPoint = ECTPoint(x: Double(px), y: Double(py))
                appState.lassoPoints.append(newPoint)
                mr.updatePreviewPoints(appState.lassoPoints)
            case .cut:
                guard let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) else { return }

                print("CUT: we add a cutting point at (\(px), \(py))")
                let newPoint = ECTPoint(x: Double(px), y: Double(py))

                appState.lassoPoints.append(newPoint)

                mr.updatePreviewPoints(appState.lassoPoints)
            case .fill:
                guard let (px, py) = convertClickToDocumentCoords(pt: pt, view: view, renderer: mr, document: doc) else { return }

                print("In fill tool, clicked at (\(px), \(py))")

                let ix = Int(px.rounded())
                let iy = Int(py.rounded())

                guard let (allVerts, allIndices) = mr.exportCurrentMesh() else {
                    print(">>> Warning: exportCurrentMesh return nil")
                    return
                }
                print("Found \(allVerts.count) vertices and \(allIndices.count) indices")

                let clickPos = SIMD2<Float>(Float(px), Float(py))

                var foundTri: (PolygonVertex, PolygonVertex, PolygonVertex)? = nil
                var foundTriIndices: (UInt16, UInt16, UInt16)? = nil

                let n = allIndices.count
                var i = 0
                while i < n {
                    let iA = allIndices[i]
                    let iB = allIndices[i + 1]
                    let iC = allIndices[i + 2]

                    let A = allVerts[Int(iA)]
                    let B = allVerts[Int(iB)]
                    let C = allVerts[Int(iC)]

                    if mr.pointInTriangle(p: clickPos, a: A.position, b: B.position, c: C.position) {
                        print("FOUND triangle at indices \(iA),\(iB),\(iC)")
                        foundTri = (A, B, C)
                        foundTriIndices = (iA, iB, iC)
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
                    UInt8(255 * selectedFillColor.x),
                    UInt8(255 * selectedFillColor.y),
                    UInt8(255 * selectedFillColor.z),
                    UInt8(255 * selectedFillColor.w)
                )

                if appState.selectedFillAlgorithm == .lca {
                    switch appState.selectedFillMode {
                    case .triangle:
                        let triPoly: [SIMD2<Float>] = [vA.position, vB.position, vC.position]
                        mr.applyFillAlgorithm(
                            algo: .lca,
                            polygon: triPoly,
                            seed: nil,
                            fillColor: fillColor,
                            fillRule: appState.selectedFillRule
                        )

                    case .polygon:
                        let pid = vA.polygonIDs.x
                        if pid < 0 {
                            print("No valid polygonID => fill only the triangle.")
                            let triPoly: [SIMD2<Float>] = [vA.position, vB.position, vC.position]
                            mr.applyFillAlgorithm(
                                algo: .lca,
                                polygon: triPoly,
                                seed: nil,
                                fillColor: fillColor,
                                fillRule: appState.selectedFillRule
                            )
                            return
                        }

                        var allPolygonsTris: [[SIMD2<Float>]] = []

                        i = 0
                        while i < n {
                            let iA = allIndices[i]
                            let iB = allIndices[i + 1]
                            let iC = allIndices[i + 2]
                            let A = allVerts[Int(iA)]
                            let B = allVerts[Int(iB)]
                            let C = allVerts[Int(iC)]

                            let matchA = (A.polygonIDs.x == pid || A.polygonIDs.y == pid || A.polygonIDs.z == pid || A.polygonIDs.w == pid)
                            let matchB = (B.polygonIDs.x == pid || B.polygonIDs.y == pid || B.polygonIDs.z == pid || B.polygonIDs.w == pid)
                            let matchC = (C.polygonIDs.x == pid || C.polygonIDs.y == pid || C.polygonIDs.z == pid || C.polygonIDs.w == pid)

                            if matchA || matchB || matchC {
                                let poly = [A.position, B.position, C.position]
                                allPolygonsTris.append(poly)
                            }
                            i += 3
                        }

                        for tri in allPolygonsTris {
                            mr.applyFillAlgorithm(
                                algo: .lca,
                                polygon: tri,
                                seed: nil,
                                fillColor: fillColor,
                                fillRule: appState.selectedFillRule
                            )
                        }
                    }
                } else {
                    // seed fill => (.seedRecursive, .seedStack, .scanline)
                    mr.applyFillAlgorithm(
                        algo: appState.selectedFillAlgorithm,
                        polygon: [],
                        seed: (ix, iy),
                        fillColor: fillColor,
                        fillRule: appState.selectedFillRule
                    )
                }
            default:
                break
            }
        }

        func mouseDragged(at pt: NSPoint, in view: NSView) {
            // If we need something for shapes or resizing
        }

        func mouseUp(at pt: NSPoint, in view: NSView) {
            // finalize shape or something
        }

        func keyPressedEnter() {
            guard let tool = appState.selectedTool else { return }
            switch tool {
            case .addPolygonFromClick:
                if appState.lassoPoints.count >= 3 {
                    guard let doc = appState.selectedDocument else { return }
                    guard let mr = mainRenderer else { return }

                    // 1) Load old mesh
                    let oldMesh = doc.loadMesh()
                    var oldVertices: [PolygonVertex] = []
                    var oldIndices: [UInt16] = []
                    if let (ov, oi) = oldMesh {
                        oldVertices = ov
                        oldIndices = oi
                    }

                    // 2) Triangulation
                    let polyID = appState.nextPolygonID
                    appState.nextPolygonID += 1

                    let color = appState.selectedColor
                    let (newVertices, newIndices) = EarClippingTriangulation.earClipOnePolygon(
                        ectPoints: appState.lassoPoints,
                        color: color,
                        existingVertexCount: oldVertices.count,
                        polygonID: polyID
                    )

                    // 3) Merge
                    let mergedVertices = oldVertices + newVertices
                    let mergedIndices = oldIndices + newIndices

                    // 4) Save doc
                    doc.saveMesh(mergedVertices, mergedIndices)

                    // 5) Update renderer
                    mr.meshRenderer.updateMesh(vertices: mergedVertices, indices: mergedIndices)

                    // 6) Fill Auto => We apply a LCA Fill to see the FillTexture shape
                    let fillC = color.toSIMD4()
                    let fillBytes = (
                        UInt8(255 * fillC.x),
                        UInt8(255 * fillC.y),
                        UInt8(255 * fillC.z),
                        UInt8(255 * fillC.w)
                    )
                    // convert lassoPoints => doc coords [SIMD2<Float>]
                    let polyFloat: [SIMD2<Float>] = appState.lassoPoints.map {
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
                appState.lassoPoints.removeAll()
                mainRenderer?.updatePreviewPoints([])
            case .cut:
                // The user has just placed appstate.lassoPoints to define the polynomial window
                guard let doc = appState.selectedDocument else { return }
                guard let mr = mainRenderer else { return }
                if appState.lassoPoints.count >= 3 {
                    // 1) Convert Lassopoints (ECTpoint/Double) to [SIMD2<Float>] (Pixel coords)
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
                        let iA = oldIndices[3 * t + 0]
                        let iB = oldIndices[3 * t + 1]
                        let iC = oldIndices[3 * t + 2]

                        let A = oldVerts[Int(iA)]
                        let B = oldVerts[Int(iB)]
                        let C = oldVerts[Int(iC)]

                        let triPoly = [A.position, B.position, C.position]

                        // 4) Triangle cutting through the "Clipwindow" window
                        let clippedPoly: [SIMD2<Float>]
                        switch appState.selectedClippingAlgorithm {
                        case .cyrusBeck:
                            clippedPoly = ClippingAlgorithms.cyrusBeckClip(
                                subjectPolygon: triPoly,
                                clipWindow: clipWindow
                            )
                        case .sutherlandHodgman:
                            clippedPoly = ClippingAlgorithms.sutherlandHodgmanClip(
                                subjectPolygon: triPoly,
                                clipWindow: clipWindow
                            )
                        }

                        // If there is no more polygon => this triangle is completely out of window
                        guard clippedPoly.count >= 3 else {
                            continue
                        }

                        // 5) We re-triangule the cut polygon (ear clipping)
                        let ectPoly = ECTPolygon(vertices: clippedPoly.map {
                            ECTPoint(x: Double($0.x), y: Double($0.y))
                        })
                        let triList = EarClippingTriangulation().getEarClipTriangles(polygon: ectPoly)

                        // 6) For each triangle produced, 3 new polygonvertex is created
                        // Keep the same color as the vertice A
                        let colorA = A.color
                        let polyIDs = A.polygonIDs // Keep the ID to find out which original poly it comes
                        for tri in triList {
                            // Convert ECTPoint -> SIMD2<Float>
                            let pA = SIMD2<Float>(Float(tri.a.x), Float(tri.a.y))
                            let pB = SIMD2<Float>(Float(tri.b.x), Float(tri.b.y))
                            let pC = SIMD2<Float>(Float(tri.c.x), Float(tri.c.y))

                            let iA2 = currentIndex
                            let iB2 = currentIndex + 1
                            let iC2 = currentIndex + 2
                            currentIndex += 3

                            newIndices.append(iA2)
                            newIndices.append(iB2)
                            newIndices.append(iC2)

                            newVertices.append(
                                PolygonVertex(position: pA,
                                              uv: .zero,
                                              color: colorA,
                                              polygonIDs: polyIDs)
                            )
                            newVertices.append(
                                PolygonVertex(position: pB,
                                              uv: .zero,
                                              color: colorA,
                                              polygonIDs: polyIDs)
                            )
                            newVertices.append(
                                PolygonVertex(position: pC,
                                              uv: .zero,
                                              color: colorA,
                                              polygonIDs: polyIDs)
                            )
                        }
                    }

                    // 7) Save this new mesh in the document
                    doc.saveMesh(newVertices, newIndices)

                    // 8) Update the rendering (Mesh GPU)
                    mr.meshRenderer.updateMesh(vertices: newVertices, indices: newIndices)

                    // 9) Re-fulfill the entire CPU texture,
                    // because we have a new mesh from the cutting
                    if let fillTex = mr.fillTexture {
                        // a) We first empty the CPU Buffer
                        let w = mr.texWidth
                        let h = mr.texHeight
                        var cpuBuf = [UInt8](repeating: 0, count: w * h * 4)
                        for i in 0..<(w * h) {
                            let idx = i * 4
                            cpuBuf[idx + 0] = 0 // R
                            cpuBuf[idx + 1] = 0 // G
                            cpuBuf[idx + 2] = 0 // B
                            cpuBuf[idx + 3] = 255 // A
                        }

                        // b) We are it on the triangles of the new mesh => we apply LCA
                        let triCount2 = newIndices.count / 3
                        for t2 in 0..<triCount2 {
                            let iA2 = newIndices[3 * t2 + 0]
                            let iB2 = newIndices[3 * t2 + 1]
                            let iC2 = newIndices[3 * t2 + 2]

                            let A2 = newVertices[Int(iA2)]
                            let B2 = newVertices[Int(iB2)]
                            let C2 = newVertices[Int(iC2)]

                            let triPoly2: [SIMD2<Float>] = [A2.position, B2.position, C2.position]

                            // Color => We take the color of A2
                            let col = A2.color
                            let fillColor = (
                                UInt8(255 * col.x),
                                UInt8(255 * col.y),
                                UInt8(255 * col.z),
                                UInt8(255 * col.w)
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

                    print("Découpage terminé, nouveau mesh mis à jour.")
                }

                // Whatever the result, we reset the lasso
                appState.lassoPoints.removeAll()
                mr.updatePreviewPoints([])
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
