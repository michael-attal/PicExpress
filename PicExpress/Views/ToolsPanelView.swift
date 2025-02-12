//
//  ToolsPanelView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftUI

/// Enum representing different tools available in the app.
enum AvailableTool: String, CaseIterable, Equatable, Identifiable, Sendable, SelectionItem {
    public var id: String { rawValue }

    case freeMove
    case fill
    case shapes
    case eraser
    case cut
    case resize
    case movePolygon
    case addPolygonList
    case addPolygonFromClick

    /// Returns the display name of the tool.
    var name: String {
        switch self {
        case .freeMove: return "Déplacement libre"
        case .fill: return "Remplissage"
        case .shapes: return "Formes"
        case .eraser: return "Gomme"
        case .cut: return "Découpage"
        case .resize: return "Redimensionnement"
        case .movePolygon: return "Déplacement d'objets"
        case .addPolygonList: return "Polygone par liste de points"
        case .addPolygonFromClick: return "Polygone par clic"
        }
    }

    /// Returns the system image associated with the tool.
    var systemImage: String {
        switch self {
        case .freeMove: return "hand.draw"
        case .fill: return "drop.fill"
        case .shapes: return "square.on.circle"
        case .eraser: return "eraser"
        case .cut: return "lasso"
        case .resize: return "hand.point.up.braille"
        case .movePolygon: return "rectangle.and.arrow.up.right.and.arrow.down.left"
        case .addPolygonList: return "hexagon.fill"
        case .addPolygonFromClick: return "hand.point.up.left"
        }
    }

    public var description: String { name }
}

/// This enum describes the different shapes we can create when using the "Formes" tool.
public enum ShapeType: String, CaseIterable, Sendable, SelectionItem {
    public var id: String { rawValue }

    case rectangle = "Rectangle"
    case square = "Carré"
    case circle = "Cercle"
    case ellipse = "Ellipse"
    case triangle = "Triangle"

    public var description: String { rawValue }
}

public enum DetectionMode: String, Identifiable, CaseIterable, Sendable, SelectionItem {
    public var id: String { rawValue }

    case triangle = "Triangle" // Fill/erase only the single triangle that was clicked
    case polygon = "Polygon" // Fill/erase the entire polygon to which that triangle belongs - Done because I added a PolygonID in each vertex (in PolygonVertex)

    public var description: String { rawValue }
}

/// Side panel: tool list
struct ToolsPanelView: View {
    /// This callback is used only for the "Polygone" (text-based) creation
    /// (when the user clicks "Appliquer" in PolygonToolView).
    let onPolygonPoints: ([ECTPoint], Color) -> Void

    @Environment(AppState.self) private var appState

    /// The array of tools displayed in the left panel
    let tools: [AvailableTool]

    @State private var selectedTool: AvailableTool? = nil
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
                get: { appState.shouldFillMeshWithBackground },
                set: { appState.shouldFillMeshWithBackground = $0 }
            )) {
                Text("Remplir l'arrière-plan")
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 4)

            Picker("Mode de détection :", selection: Binding<DetectionMode>(
                get: { appState.selectedDetectionMode },
                set: { appState.selectedDetectionMode = $0 }
            )) {
                ForEach(DetectionMode.allCases, id: \.self) { fillMode in
                    Text(fillMode.rawValue)
                }
            }.frame(maxWidth: 350)

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

            Button(action: {
                let panel = NSSavePanel()
                panel.allowedFileTypes = ["png"]
                panel.nameFieldStringValue = appState.selectedDocument?.name != nil ? "\(appState.selectedDocument!.name).png" : "Untitled.png"
                panel.begin { result in
                    if result == .OK, let url = panel.url, let mtkView = appState.mainCoordinator?.metalView {
                        mtkView.exportToPNG(saveURL: url)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Exporter en PNG")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
            .cornerRadius(4)
        }
        .padding(.horizontal)
        // Generic selection sheet
        .sheet(isPresented: $showSelectionSheet) {
            if let handler = selectionHandler {
                SelectionSheetView<AnySelectionItem>(
                    title: selectionTitle,
                    options: selectionOptions,
                    isPresented: $showSelectionSheet,
                    onSelection: { selectedAnyItem in
                        print("Selected tool: \(selectedAnyItem)")
                        handler(selectedAnyItem)
                    },
                    onCancel: {
                        selectedTool = nil
                    }
                )
            }
        }
        // If the user picks "Polygone" => show text-based polygon
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
    private func handleToolSelected(_ tool: AvailableTool) {
        print("Tool selected: \(tool.name)")
        selectedTool = tool
        showPolygonSheet = false
        showSelectionSheet = false

        switch tool {
        case .addPolygonList:
            // Ask the user for the polygon algorithm
            showSelectionSheet(
                title: "Choisir l'algorithme de triangulation pour le polygone",
                options: AvailableTriangulationAlgorithm.allCases
            ) { algo in
                appState.selectedTriangulationAlgorithm = algo
                showPolygonSheet = true
            }

        case .addPolygonFromClick:
            showSelectionSheet(
                title: "Choisir l'algorithme de triangulation pour le polygone (clic)",
                options: AvailableTriangulationAlgorithm.allCases
            ) { algo in
                appState.selectedTriangulationAlgorithm = algo
            }

        case .fill:
            showSelectionSheet(
                title: "Choisir l'algorithme de remplissage",
                options: [AvailableFillAlgorithm.seedRecursive, .seedStack, .scanline, .lca]
            ) { algo in
                appState.selectedFillAlgorithm = algo
            }

        case .cut:
            showSelectionSheet(
                title: "Choisir l'algorithme de découpage",
                options: AvailableClippingAlgorithm.allCases
            ) { algo in
                appState.selectedClippingAlgorithm = algo
            }

        case .shapes:
            // By default use Ear Clipping for triangulation
            showSelectionSheet(
                title: "Choisir la forme à dessiner",
                options: ShapeType.allCases
            ) { shape in
                appState.currentShapeType = shape
            }

        case .resize:
            // No need to ask an algo => user just wants to move vertices
            // We do nothing special here
            print("Mode: Redimensionnement => user can drag the lassoPoints vertices now")

        default:
            break
        }

        // Let the coordinator update (dis)able pan, etc.
        appState.mainCoordinator?.updatePanGestureEnabled()
    }

    /// Helper function to show the selection sheet with a typed array of T: SelectionItem.
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
