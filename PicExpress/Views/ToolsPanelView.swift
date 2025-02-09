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

    // For fill tool:
    @State private var showFillAlgorithmMenu = false

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
        // If the user picks "Polygone", we show a sheet
        .sheet(isPresented: $showPolygonSheet) {
            PolygonToolView { points, color in
                onPolygonPoints(points, color)
            }
        }
        // The FillAlgorithm selection can also be shown in a sheet or a menu
        .confirmationDialog("Choisir l'algorithme de remplissage", isPresented: $showFillAlgorithmMenu) {
            ForEach(FillAlgorithm.allCases) { algo in
                Button(algo.rawValue) {
                    appState.fillAlgorithm = algo
                }
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

        switch tool.name {
        case "Polygone":
            // If it's the textual polygon creation, open the sheet
            showPolygonSheet = true

        case "Remplissage":
            // We show a dialog or a menu to pick the fill algorithm
            showFillAlgorithmMenu = true

        default:
            break
        }
    }
}
