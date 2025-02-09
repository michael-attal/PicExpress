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

/// This enum describes the different shapes we can create when using the "Formes" tool.
public enum ShapeType: String, CaseIterable, Sendable, SelectionItem {
    case rectangle
    case square
    case circle
    case ellipse
    case triangle

    public var description: String { rawValue }
}

/// Side panel: tool list
struct ToolsPanelView: View {
    /// This callback is used only for the "Polygone" (text-based) creation
    /// (when the user clicks "Appliquer" in PolygonToolView).
    let onPolygonPoints: ([ECTPoint], Color) -> Void

    @Environment(AppState.self) private var appState

    /// The array of tools displayed in the left panel
    let tools: [Tool]

    @State private var selectedTool: Tool? = nil
    @State private var showPolygonSheet = false

    // For the selection sheet
    @State private var showSelectionSheet = false
    @State private var selectionTitle = ""

    // We store items as [AnySelectionItem]
    @State private var selectionOptions: [AnySelectionItem] = []
    // The handler calls back when user picks an item
    @State private var selectionHandler: ((AnySelectionItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outils")
                .font(.headline)

            // Background color picker
            HStack {
                Text("Fond :")
                ColorPicker("",
                            selection: Binding<Color>(
                                get: { appState.selectedBackgroundColor },
                                set: { appState.selectedBackgroundColor = $0 }
                            ),
                            supportsOpacity: true)
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
                ColorPicker("",
                            selection: Binding<Color>(
                                get: { appState.selectedColor },
                                set: { appState.selectedColor = $0 }
                            ),
                            supportsOpacity: true)
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
                .background(selectedTool == tool ? Color.blue.opacity(0.2) : Color.clear)
                .cornerRadius(4)
            }
        }
        .padding(.horizontal)
        // Generic selection sheet
        .sheet(isPresented: $showSelectionSheet) {
            if let handler = selectionHandler {
                SelectionSheetView<AnySelectionItem>(
                    title: selectionTitle,
                    options: selectionOptions,
                    isPresented: $showSelectionSheet
                ) { selectedAnyItem in
                    handler(selectedAnyItem)
                }
            }
        }
        // If the user picks "Polygone", we show a sheet
        .sheet(isPresented: $showPolygonSheet) {
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
    }

    /// Called when the user taps on a tool
    private func handleToolSelected(_ tool: Tool) {
        print("Tool selected: \(tool.name)")
        selectedTool = tool
        showPolygonSheet = false
        showSelectionSheet = false

        switch tool.name {
        case "Polygone":
            // Ask the user for the polygon algorithm
            showSelectionSheet(
                title: "Choisir l'algorithme de clipping pour le polygone",
                options: PolygonClippingAlgorithm.allCases
            ) { algo in
                appState.selectedPolygonAlgorithm = algo
                showPolygonSheet = true
            }

        case "Polygone par clic":
            showSelectionSheet(
                title: "Choisir l'algorithme de clipping pour le polygone",
                options: PolygonClippingAlgorithm.allCases
            ) { algo in
                appState.selectedPolygonAlgorithm = algo
            }

        case "Remplissage":
            showSelectionSheet(
                title: "Choisir l'algorithme de remplissage",
                options: FillAlgorithm.allCases
            ) { algo in
                appState.fillAlgorithm = algo
            }

        case "Découpage":
            showSelectionSheet(
                title: "Choisir l'algorithme de découpage",
                options: PolygonClippingAlgorithm.allCases
            ) { algo in
                appState.selectedPolygonAlgorithm = algo
            }

        case "Formes":
            showSelectionSheet(
                title: "Choisir la forme à dessiner",
                options: ShapeType.allCases
            ) { shape in
                appState.currentShapeType = shape
            }

        default:
            break
        }

        appState.mainCoordinator?.updatePanGestureEnabled()
    }

    /// Helper function to show the selection sheet with a typed array of T: SelectionItem.
    /// We convert them into [AnySelectionItem] to store in `selectionOptions`.
    private func showSelectionSheet<T: SelectionItem>(
        title: String,
        options: [T],
        handler: @escaping (T) -> Void
    ) {
        // 1) store the title
        selectionTitle = title

        // 2) convert to [AnySelectionItem]
        selectionOptions = options.map { AnySelectionItem($0) }

        // 3) store the final callback
        selectionHandler = { anyItem in
            // cast back to T
            if let typedItem = anyItem.base as? T {
                handler(typedItem)
            }
        }

        // 4) show the sheet
        showSelectionSheet = true
    }
}
