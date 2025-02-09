//
//  ToolsPanelView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftUI

/// Represents a tool in the panel
struct Tool: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let systemImage: String
}

/// Side panel: tool list
struct ToolsPanelView: View {
    /// This callback is used only for the "Polygone" (text-based) creation (when the user clicks "Appliquer" in PolygonToolView)
    let onPolygonPoints: ([ECTPoint], Color) -> Void

    @Environment(AppState.self) private var appState

    /// The array of tools displayed in the left panel
    let tools: [Tool]

    @State private var selectedTool: Tool? = nil
    @State private var showPolygonSheet = false
    @State private var showPolygonSheetTwo = false // Dumb way to display a sheet after another (in my case, the confirmation dialogue for the selected clipping algorithm BEFORE the PolygonToolView).

    @State private var showFillAlgorithmMenu = false
    @State private var showPolygonClippingAlgoMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outils")
                .font(.headline)

            // Background color picker
            HStack {
                Text("Fond :")
                ColorPicker("", selection: Binding<Color>(
                    get: { appState.selectedBackgroundColor },
                    set: { appState.selectedBackgroundColor = $0 }
                ), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 50, height: 25)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(4)

            // Drawing color picker
            HStack {
                Text("Couleur :")
                ColorPicker("", selection: Binding<Color>(
                    get: { appState.selectedColor },
                    set: { appState.selectedColor = $0 }
                ), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 50, height: 25)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(4)

            Toggle(isOn: Binding<Bool>(
                get: { appState.pixelFillEnabled },
                set: { appState.pixelFillEnabled = $0 }
            )) {
                Text("Mode pixel fill")
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 4)

            Toggle(isOn: Binding<Bool>(
                get: { appState.fillPolygonBackground },
                set: { appState.fillPolygonBackground = $0 }
            )) {
                Text("Remplir l'arrière-plan du polygone")
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 4)

            // List of tools (buttons)
            ForEach(tools) { tool in
                Button(action: {
                    handleToolSelected(tool)
                }) {
                    HStack {
                        Image(systemName: tool.systemImage)
                        Text(tool.name)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity)
                .background(
                    selectedTool == tool ? Color.blue.opacity(0.2) : Color.clear
                )
                .cornerRadius(4)
            }
        }
        .padding(.horizontal)
        // The FillAlgorithm selection can also be shown in a sheet or a menu
        .confirmationDialog("Choisir l'algorithme de remplissage", isPresented: $showFillAlgorithmMenu) {
            ForEach(FillAlgorithm.allCases) { algo in
                Button(algo.rawValue) {
                    appState.fillAlgorithm = algo
                }
            }
            // Button("Annuler", role: .cancel) {} If uncommented, hide the LCA fill option, idk why
        }
        // The polygon algorithm selection dialog
        .confirmationDialog("Choisir l'algorithme de clipping pour le polygone", isPresented: $showPolygonClippingAlgoMenu) {
            ForEach(PolygonClippingAlgorithm.allCases) { algo in
                Button(algo.rawValue) {
                    appState.selectedPolygonAlgorithm = algo
                    if showPolygonSheet {
                        showPolygonSheetTwo = true
                    }
                }
            }
            Button("Annuler", role: .cancel) {}
        }
        // If the user picks "Polygone", we show a sheet
        .sheet(isPresented: $showPolygonSheetTwo) {
            PolygonToolView { points, color in
                onPolygonPoints(points, color)
            }
        }
        .onAppear {
            selectedTool = appState.selectedTool
        }
        .onChange(of: selectedTool) { newValue in
            appState.selectedTool = newValue
        }
        .onChange(of: appState.selectedTool) { newValue in
            selectedTool = newValue
        }
    }

    /// Called when the user taps on a tool
    private func handleToolSelected(_ tool: Tool) {
        print("Tool selected: \(tool.name)")
        selectedTool = tool
        showPolygonSheet = false
        showFillAlgorithmMenu = false
        showPolygonClippingAlgoMenu = false

        switch tool.name {
        case "Polygone":
            // Ask the user for the polygon algorithm
            showPolygonClippingAlgoMenu = true
            // Then open the sheet for textual polygon creation
            showPolygonSheet = true

        case "Polygone par clic":
            // As the user will click in the canvas, we ask for the polygon algorithm as well
            showPolygonClippingAlgoMenu = true

        case "Remplissage":
            // We show a dialog or a menu to pick the fill algorithm
            showFillAlgorithmMenu = true

        case "Découpage":
            // The user draws a lasso in the metal canvas => see the coordinator
            // Possibly we also want to ask which polygon algorithm to use for final clipping
            showPolygonClippingAlgoMenu = true

        default:
            break
        }
    }
}
