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

                // MARK: - onPolygonPoints

                // Updated to convert from [-1..1] NDC to [0..docWidth] pixel coords
                onPolygonPoints: { newPoints, color in
                    guard let doc = appState.selectedDocument else { return }
                    guard let mainRenderer = appState.mainRenderer else { return }

                    // If your input is in "normalized device coords" around [-1..1],
                    // convert them to pixel coords:
                    let docWidth = Double(doc.width)
                    let docHeight = Double(doc.height)

                    // This maps (-1, -1) => (0, 0) and (1, 1) => (docWidth, docHeight),
                    // so the shape is now within the full canvas.
                    let convertedPoints = newPoints.map { original -> ECTPoint in
                        let px = (original.x + 1.0) * 0.5 * docWidth
                        let py = (original.y + 1.0) * 0.5 * docHeight
                        return ECTPoint(x: px, y: py)
                    }

                    // Retrieve old mesh from document if any
                    let oldMesh = doc.loadMesh()
                    var oldVertices: [PolygonVertex] = []
                    var oldIndices: [UInt16] = []

                    if let (ov, oi) = oldMesh {
                        oldVertices = ov
                        oldIndices = oi
                    }

                    // Triangulate the new polygon => newVertices + newIndices
                    let (newVertices, newIndices) = EarClippingTriangulation.earClipOnePolygon(
                        ectPoints: convertedPoints,
                        color: color,
                        existingVertexCount: oldVertices.count
                    )

                    // Merge old + new
                    let mergedVertices = oldVertices + newVertices
                    let mergedIndices = oldIndices + newIndices

                    // Save doc
                    doc.saveMesh(mergedVertices, mergedIndices)

                    // Update renderer
                    mainRenderer.meshRenderer.updateMesh(vertices: mergedVertices, indices: mergedIndices)
                }
            )
            .navigationTitle("PicExpress")
            .navigationSplitViewColumnWidth(min: 10, ideal: 120, max: 200)

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

    private func addDocument(docName: String, width: Int, height: Int) {
        withAnimation {
            let newDoc = PicExpressDocument(name: docName,
                                            width: width,
                                            height: height)
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
