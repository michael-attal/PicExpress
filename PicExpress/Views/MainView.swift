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

    /// Basic startup tools (edit later from required tools of syllabus)
    private let tools: [Tool] = [
        Tool(name: "Remplissage", systemImage: "drop.fill"),
        Tool(name: "Gomme", systemImage: "eraser"),
        Tool(name: "Formes", systemImage: "square.on.circle"),
        // Tool(name: "Recadrage", systemImage: "crop"),
        Tool(name: "Polygone", systemImage: "hexagon.fill"),
        Tool(name: "Polygone par clic", systemImage: "hand.point.up.left")
    ]

    var body: some View {
        NavigationSplitView {
            LeftPanelView(
                documents: documents,
                selectedDocument: $selectedDocument,
                onAddDocument: addDocument,
                onDeleteDocument: deleteDocument,
                tools: tools,
                onPolygonPoints: { points, color in
                    // Directly store via appState
                    appState.storePolygonInDocument(points, color: color)
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

    private func addDocument() {
        withAnimation {
            let newDoc = PicExpressDocument(name: "Nouveau Document")
            modelContext.insert(newDoc)
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
    }
}
