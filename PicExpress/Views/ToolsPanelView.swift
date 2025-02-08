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
    /// This callback is used only for the "Polygone" (text-based) creation (when the user clicks "Appliquer" dans PolygonToolView)
    let onPolygonPoints: ([ECTPoint], Color) -> Void

    @Environment(AppState.self) private var appState

    /// The array of tools displayed in the left panel
    let tools: [Tool]

    @State private var selectedTool: Tool? = nil
    @State private var showPolygonSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outils")
                .font(.headline)

            // New color picker for background color
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

            // Existing color picker for drawing color
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
        .sheet(isPresented: $showPolygonSheet) {
            /// PolygonToolView is the sheet used for text-based polygon creation
            PolygonToolView { points, color in
                onPolygonPoints(points, color)
            }
        }
        // When the panel appears or the user selects a tool, update local state
        .onAppear {
            selectedTool = appState.selectedTool
        }
        .onChange(of: selectedTool) { newValue in
            // Update appState when the user picks a tool
            appState.selectedTool = newValue
        }
        .onChange(of: appState.selectedTool) { newValue in
            // If external code changes appState.selectedTool, reflect it here
            selectedTool = newValue
        }
    }

    /// Called when the user taps on a tool
    private func handleToolSelected(_ tool: Tool) {
        print("Tool selected: \(tool.name)")
        selectedTool = tool
        showPolygonSheet = false

        // If it's the textual polygon creation, open the sheet
        if tool.name == "Polygone" {
            showPolygonSheet = true
        }
    }
}
