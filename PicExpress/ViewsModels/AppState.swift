//
//  AppState.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import Foundation
import SwiftUI

@Observable
@MainActor final class AppState: Sendable {
    static let isDevelopmentMode = false
    static let isDebugMode = false

    /// The main metal renderer created by MetalCanvasView
    var mainRenderer: MainMetalRenderer?

    // We keep a reference to the coordinator so we can call updatePanGestureEnabled
    weak var mainCoordinator: MetalCanvasView.Coordinator?

    /// The currently opened document (if any)
    var selectedDocument: PicExpressDocument?

    /// Indicates whether the user has opened a document or not
    var isDocumentOpen: Bool = false

    /// The color used for drawing polygons (or other shapes)
    var selectedColor: Color = .yellow

    /// The color used for the Metal canvas background (clearColor)
    var selectedBackgroundColor: Color = .black

    /// The currently selected tool in the left panel
    var selectedTool: AvailableTool? = .freeMove

    /// The fill algorithm chosen by the user (seed recursive, seed stack, scanline, LCA)
    var selectedFillAlgorithm: AvailableFillAlgorithm = .seedRecursive

    /// Should we fill mesh polygons interiors with color or only draw outlines
    var shouldFillMeshWithBackground: Bool = true

    /// Which clipping algorithm to use
    var selectedClippingAlgorithm: AvailableClippingAlgorithm = .sutherlandHodgman

    /// Which triangulation algorithm to use
    var selectedTriangulationAlgorithm: AvailableTriangulationAlgorithm = .earClipping

    /// When user picks the "Découpage" tool, we store the points of the freehand or clicked polygon:
    var lassoPoints: [ECTPoint] = []

    /// For the shape tool, we store the current shape type if the user chooses "Formes".
    var currentShapeType: ShapeType? = nil

    // The fill rule => evenOdd (pair-impair) or winding (enroulement) or both
    var selectedFillRule: FillRule = .evenOdd

    /// Store or build a single big mesh in the doc + mainRenderer.
    ///
    /// - parameter polygons: an array of polygons, each polygon is a list of ECTPoint
    ///   for example if the user is making multiple shapes at once,
    ///   or you can pass just one polygon in a list of size=1.
    /// - parameter color: SwiftUI color for the mesh.
    func storeMeshInDocument(_ polygons: [[ECTPoint]], color: Color) {
        guard let doc = selectedDocument else {
            print("No document selected.")
            return
        }

        // 1) Convert SwiftUI.Color to RGBA float
        let uiColor = NSColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if let converted = uiColor.usingColorSpace(.deviceRGB) {
            converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        } else {
            print("Cannot convert color space.")
        }
        let colorVec = SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))

        // 2) Convert your ECTPoints => arrays de SIMD2<Float>
        //    Car mainRenderer.buildGlobalMesh(...) prend des [SIMD2<Float>]
        let polygonsF: [[SIMD2<Float>]] = polygons.map { polyECT in
            polyECT.map { pt in SIMD2<Float>(Float(pt.x), Float(pt.y)) }
        }

        // 3) Build the big mesh => calls ear clipping, etc.
        //    We can pick an algo de clipping if we want
        mainRenderer?.buildGlobalMesh(
            polygons: polygonsF,
            clippingAlgorithm: selectedClippingAlgorithm, // or nil if no clipping
            clipWindow: [], // or some polygon for window
            color: colorVec
        )

        if let (verts, inds) = mainRenderer?.exportCurrentMesh() {
            doc.saveMesh(verts, inds)
            print("storeMeshInDocument: doc meshData updated.")
        } else {
            print("storeMeshInDocument: no mesh to save")
        }
    }
}
