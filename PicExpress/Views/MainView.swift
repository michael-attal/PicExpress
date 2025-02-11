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

    private let tools: [Tool] = [
        Tool(name: "Déplacement libre", systemImage: "hand.draw"),
        Tool(name: "Remplissage", systemImage: "drop.fill"),
        Tool(name: "Gomme", systemImage: "eraser"),
        Tool(name: "Formes", systemImage: "square.on.circle"),
        Tool(name: "Découpage", systemImage: "lasso"),
        // Tool(name: "Recadrage", systemImage: "crop"),
        Tool(name: "Redimensionnement", systemImage: "hand.point.up.braille"),
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
