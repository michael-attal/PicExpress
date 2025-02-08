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
    let tools: [Tool]
    
    @Environment(AppState.self) private var appState
    
    // This callback is used only for the "Polygone" (text-based) creation
    let onPolygonPoints: ([ECTPoint], Color) -> Void
    
    @State private var selectedTool: Tool? = nil
    
    @State private var showPolygonSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outils")
                .font(.headline)
            
            HStack {
                Image(systemName: "paintpalette")
                ColorPicker("", selection: Binding<Color>(
                    get: { appState.selectedColor },
                    set: { appState.selectedColor = $0 }
                ), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 50, height: 25)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(4)

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
            PolygonToolView { points, color in
                onPolygonPoints(points, color)
            }
        }
        .onChange(of: appState.isClickPolygonMode) { newValue in
            // If we just turned it OFF and it was the "Polygone par clic" tool, unselect.
            // TODO: Later save directly the selected tool in the appState.
            if !newValue, selectedTool?.name == "Polygone par clic" {
                selectedTool = nil
            }
        }
    }

    private func handleToolSelected(_ tool: Tool) {
        print("Tool selected: \(tool.name)")
        selectedTool = tool
        
        showPolygonSheet = false
        appState.isClickPolygonMode = false
        
        // If it's the textual polygon tool, open the sheet
        if tool.name == "Polygone" {
            showPolygonSheet = true
        }
        // If it's the "Polygone par clic" tool, enable the mode
        else if tool.name == "Polygone par clic" {
            appState.isClickPolygonMode = true
        }
        else {
            // TODO: Handle other tools as needed
        }
    }
}
