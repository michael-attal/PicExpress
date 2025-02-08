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
                    storePolygon(points: points, color: color)
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

    /// Stores a polygon (points + color) in doc (JSON) and displays it immediately.
    private func storePolygon(points: [ECTPoint], color: Color) {
        guard let doc = selectedDocument else { return }

        // Convert SwiftUI.Color -> RGBA (deviceRGB)
        let uiColor = NSColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if let converted = uiColor.usingColorSpace(.deviceRGB) {
            converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        } else {
            print("Impossible de convertir la couleur (catalog color?).")
        }

        // 1) Load existing list
        var existingPolygons = doc.loadAllPolygons()

        // 2) Building a new StoredPolygon
        let points2D = points.map { Point2D(x: $0.x, y: $0.y) }
        let colorArray = [Float(red), Float(green), Float(blue), Float(alpha)]
        let newPoly = StoredPolygon(points: points2D, color: colorArray)

        // 3) Add + save
        existingPolygons.append(newPoly)
        doc.saveAllPolygons(existingPolygons)
        print("Now doc has \(existingPolygons.count) polygons stored.")

        // 4) Immediate display in mainRenderer
        let colorVec = SIMD4<Float>(colorArray[0], colorArray[1], colorArray[2], colorArray[3])
        appState.mainRenderer?.addPolygon(points: points, color: colorVec)
    }
}
