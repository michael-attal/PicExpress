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

    /// The currently opened document (if any)
    var selectedDocument: PicExpressDocument?

    /// Indicates whether the user has opened a document or not
    var isDocumentOpen: Bool = false

    /// The color used for drawing polygons (or other shapes)
    var selectedColor: Color = .yellow

    /// The color used for the Metal canvas background (clearColor)
    var selectedBackgroundColor: Color = .black

    /// The currently selected tool in the left panel
    var selectedTool: Tool? = nil

    /// The fill algorithm chosen by the user (seed recursive, seed stack, scanline, LCA)
    var fillAlgorithm: FillAlgorithm = .seedRecursive

    /// If true, we do a pixel-based fill in a texture. If false, we simply recolor the polygon
    var pixelFillEnabled: Bool = false

    /// Stores the given polygon in the current selectedDocument, then displays it immediately.
    func storePolygonInDocument(_ points: [ECTPoint], color: Color) {
        guard let doc = selectedDocument else { return }

        // Convert SwiftUI.Color -> RGBA
        let uiColor = NSColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if let converted = uiColor.usingColorSpace(.deviceRGB) {
            converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        } else {
            print("Impossible to convert color (catalog color?).")
        }

        // 1) Load existing polygons from the document
        var existingPolygons = doc.loadAllPolygons()

        // 2) Build a new StoredPolygon
        let points2D = points.map { Point2D(x: $0.x, y: $0.y) }
        let colorArray = [Float(red), Float(green), Float(blue), Float(alpha)]
        let newPoly = StoredPolygon(points: points2D, color: colorArray)

        // 3) Append and save
        existingPolygons.append(newPoly)
        doc.saveAllPolygons(existingPolygons)
        print("Now doc has \(existingPolygons.count) polygons stored.")

        // 4) Immediately display it in the mainRenderer
        let colorVec = SIMD4<Float>(colorArray[0], colorArray[1], colorArray[2], colorArray[3])
        mainRenderer?.addPolygon(points: points, color: colorVec)
    }
}
