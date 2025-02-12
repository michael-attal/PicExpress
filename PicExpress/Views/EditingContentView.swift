//
//  EditingContentView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import SwiftData
import SwiftUI

enum RendererOptions: String, CaseIterable, Identifiable {
    case defaultMesh = "Par défaut (Mesh unique)"

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

    @State private var selectedRenderers: Set<RendererOptions> = [.defaultMesh]

    var body: some View {
        VStack(spacing: 0) {
            if appState.selectedTool == .addPolygonFromClick || appState.selectedTool == .cut {
                Text("Cliquez sur au moins trois points pour créer une forme. Appuyez sur Entrée pour valider.")
                    .padding(8)
                    .foregroundColor(.yellow)
            }
            // else if appState.selectedTool == .resize {
            //     Text("Cliquez sur un sommet existant pour le déplacer. Faites un glisser (drag) pour modifier la forme.")
            //         .padding(8)
            //         .foregroundColor(.yellow)
            // }

            // --- Metal canvas zone ---
            MetalCanvasView(
                zoom: $zoom,
                panOffset: $panOffset
            )
            .aspectRatio(CGFloat(appState.selectedDocument?.width ?? 1) / CGFloat(appState.selectedDocument?.height ?? 1), contentMode: .fit)
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
                                    Label(
                                        "\(option.rawValue) \(selectedRenderers.contains(option) ? "☑︎" : "□")",
                                        systemImage: selectedRenderers.contains(option) ? "checkmark" : ""
                                    )
                                }
                            }
                        } label: {
                            Text("Renderer(s)")
                        }
                        .frame(width: 100)
                    }
                }
            }
        }
        .onChange(of: document) {
            clearPreviousMesh()
            loadMeshFromDocument()
        }
        .task {
            // Load and display the mesh when the view appears (and also on doc change)
            loadMeshFromDocument()
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

    private func updateRenderers() {}

    // MARK: - loadMeshFromDocument

    /// We read the mesh from the doc, then update the main renderer's mesh.
    private func loadMeshFromDocument() {
        guard let mainRenderer = appState.mainRenderer else {
            return
        }
        // 1) Clear existing mesh
        clearPreviousMesh()

        // 2) Check if the doc has a saved mesh
        if let (vertices, indices) = document.loadMesh() {
            // 3) Send this mesh to the renderer
            mainRenderer.meshRenderer.updateMesh(vertices: vertices, indices: indices)
            print("loadMeshFromDocument: Mesh loaded from doc and updated in mainRenderer.")
        } else {
            print("loadMeshFromDocument: No mesh found in doc.")
        }
    }

    // MARK: - clearPreviousMesh

    /// Replaces clearPreviousPolygon. We clear the mesh in the mainRenderer (sets empty buffers).
    private func clearPreviousMesh() {
        guard let mainRenderer = appState.mainRenderer else {
            return
        }
        mainRenderer.meshRenderer.updateMesh(vertices: [], indices: [])
        print("clearPreviousMesh: Emptied the big mesh from mainRenderer.")
    }
}
