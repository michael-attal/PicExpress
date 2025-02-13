//
//  MainView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import AppKit
import SwiftData
import SwiftUI

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query private var documents: [PicExpressDocument]
    @State private var selectedDocument: PicExpressDocument?

    /// List of available tools using ToolType enum.
    private let tools: [AvailableTool] = AvailableTool.allCases

    var body: some View {
        NavigationSplitView {
            LeftPanelView(
                documents: documents,
                selectedDocument: $selectedDocument,
                onAddDocument: addDocument,
                onDeleteDocument: deleteDocument,
                tools: tools,
                onPolygonPoints: { newPoints, color in
                    guard let doc = appState.selectedDocument else { return }
                    guard let mainRenderer = appState.mainRenderer else { return }

                    // Convert from [-1..1] coords to doc pixel coords
                    let docWidth = Double(doc.width)
                    let docHeight = Double(doc.height)

                    let convertedPoints = newPoints.map { original -> ECTPoint in
                        let px = (original.x + 1.0) * 0.5 * docWidth
                        let py = (original.y + 1.0) * 0.5 * docHeight
                        return ECTPoint(x: px, y: py)
                    }

                    // Load the existing mesh (if any)
                    let oldMesh = doc.loadMesh()
                    var oldVertices: [PolygonVertex] = []
                    var oldIndices: [UInt16] = []

                    if let (ov, oi) = oldMesh {
                        oldVertices = ov
                        oldIndices = oi
                    }

                    let newPolyID = appState.nextPolygonID
                    appState.nextPolygonID += 1

                    // Triangulation
                    let (newVertices, newIndices) = EarClippingTriangulation.earClipOnePolygon(
                        ectPoints: convertedPoints,
                        color: color,
                        existingVertexCount: oldVertices.count,
                        polygonID: newPolyID
                    )

                    // Merge old + new
                    let mergedVertices = oldVertices + newVertices
                    let mergedIndices = oldIndices + newIndices

                    // Save doc
                    doc.saveMesh(mergedVertices, mergedIndices)

                    // Update renderer
                    mainRenderer.meshRenderer.updateMesh(vertices: mergedVertices, indices: mergedIndices)

                    let fillColor = color.toSIMD4()
                    let fillColorBytes = (
                        UInt8(255 * fillColor.x),
                        UInt8(255 * fillColor.y),
                        UInt8(255 * fillColor.z),
                        UInt8(255 * fillColor.w)
                    )

                    // Convert ECTPoint -> [SIMD2<Float>] to doc coords
                    let polyFloat: [SIMD2<Float>] = convertedPoints.map {
                        SIMD2<Float>(Float($0.x), Float($0.y))
                    }

                    mainRenderer.applyFillAlgorithm(
                        algo: .lca,
                        polygon: polyFloat,
                        seed: nil,
                        fillColor: fillColorBytes,
                        fillRule: .evenOdd
                    )
                }
            )
            .navigationTitle("PicExpress")
            .navigationSplitViewColumnWidth(min: 100, ideal: 150, max: 250)

        } detail: {
            if let doc = selectedDocument {
                EditingContentView(document: doc)
            } else {
                Text("Sélectionnez un document ou créez-en un nouveau.")
                    .foregroundColor(.secondary)
                    .navigationTitle("Aucun document sélectionné")
            }
        }
    }

    // MARK: - Actions

    private func addDocument(docName: String, width: Int, height: Int, meshData: Data? = nil, fillTexture: Data? = nil) {
        withAnimation {
            let newDoc = PicExpressDocument(name: docName,
                                            width: width,
                                            height: height,
                                            meshData: meshData,
                                            fillTexture: fillTexture)
            modelContext.insert(newDoc)
            appState.selectedTool = tools.first
            selectedDocument = newDoc
        }
    }

    private func deleteDocument(_ doc: PicExpressDocument) {
        if doc == selectedDocument {
            selectedDocument = nil
        }

        withAnimation {
            modelContext.delete(doc)
        }

        appState.selectedTool = tools.first
    }
}
