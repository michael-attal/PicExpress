//
//  EditingContentView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftData
import SwiftUI

enum RendererOptions: String, CaseIterable, Identifiable {
    case polygon = "Polygone"
    case triangle = "Triangle"
    case circle = "Cercle"

    var id: String { rawValue }
}

struct EditingContentView: View {
    @Environment(AppState.self) private var appState

    /// The document being edited
    @Bindable var document: PicExpressDocument

    @State private var isEditingDocumentName = false

    // Zoom and pan for MetalCanvasView
    @State private var zoom: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero

    // Display triangle or not (for testing multiple renderer in metal)
    @State private var showTriangle = false

    @State private var selectedRenderers: Set<RendererOptions> = [.polygon]

    var body: some View {
        VStack(spacing: 0) {
            // --- Metal canvas zone ---
            // RotationMetalCanvasTestView(contentMode: .fit)
            MetalCanvasView(
                zoom: $zoom,
                panOffset: $panOffset,
                showTriangle: $showTriangle
            )
        }
        .navigationTitle(document.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    HStack {
                        if isEditingDocumentName {
                            TextField("Nom du document", text: $document.name)
                                .padding(0)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 240)
                        } else {
                            VStack(alignment: .leading) {
                                Text("Édition du document : \(document.name)")
                                    .font(.title3)
                                Text("Date : \(Utils.localizedDateString(from: document.timestamp)) - \(Utils.localizedTimeString(from: document.timestamp))")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            isEditingDocumentName.toggle()
                        } label: {
                            Text(isEditingDocumentName ? "Valider" : "Renommer").frame(minWidth: 72)
                        }
                        .padding(.leading, 8)

                        // A Menu picker to show/hide some renderer (like the triangle renderer test)
                        Menu {
                            ForEach(RendererOptions.allCases) { option in
                                Button {
                                    toggleRendererOption(option)
                                } label: {
                                    Label("\(option.rawValue) \(selectedRenderers.contains(option) ? "☑︎" : "□")", systemImage: selectedRenderers.contains(option) ? "checkmark" : "")
                                }
                            }
                        } label: {
                            Text("Renderer(s)")
                        }.frame(width: 100)
                    }
                }
            }
        }
        .onChange(of: document) {
            clearPreviousPolygon()
            loadPolygonsFromDocument()
        }
        .task {
            // Load and display the list of polygons in the document first time the view appear and then onChange above
            loadPolygonsFromDocument()
        }
    }

    private func toggleRendererOption(_ option: RendererOptions) {
        if selectedRenderers.contains(option) {
            selectedRenderers.remove(option)
        } else {
            selectedRenderers.insert(option)
        }
        updateRenderers()
    }

    /// Update canvas metal according to selected renderer
    private func updateRenderers() {
        showTriangle = selectedRenderers.contains(.triangle)
        // TODO: showPolygon (add inside metal canvas view the boolean... like for showing the triangle renderer)
    }

    /// Reads doc.verticesData (via loadAllPolygons()) then
    /// adds each polygon to the mainRenderer.
    private func loadPolygonsFromDocument() {
        guard let mainRenderer = appState.mainRenderer else {
            print("No mainRenderer found in appState.")
            return
        }

        // Load existing polygon list
        let storedPolygons = document.loadAllPolygons()
        for sp in storedPolygons {
            // Convert [Point2D] -> [ECTPoint]
            let ectPoints = sp.points.map { ECTPoint(x: $0.x, y: $0.y) }
            // Convert [Float] -> SIMD4<Float>
            let c = SIMD4<Float>(sp.color[0], sp.color[1], sp.color[2], sp.color[3])
            // Add it to renderer
            mainRenderer.addPolygon(points: ectPoints, color: c)
        }
    }

    private func clearPreviousPolygon() {
        guard let mainRenderer = appState.mainRenderer else {
            print("No mainRenderer found in appState.")
            return
        }

        mainRenderer.clearPolygons()
    }
}
