//
//  PicExpressDocument.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import Foundation
import SwiftData

/// Represents an encodable 2D point
struct Point2D: Codable {
    let x: Double
    let y: Double
}

/// Represents a stored polygon: list of points + RGBA color
struct StoredPolygon: Codable {
    let points: [Point2D]
    let color: [Float] // (r, g, b, a)
}

@Model
final class PicExpressDocument {
    /// Document name
    var name: String

    var createdAt: Date = Date()
    
    /// Date last modified
    var timestamp: Date

    /// The "pixel width" and "pixel height" of our canvas
    var width: Int
    var height: Int

    /// Binary storage of polygons (serialized in JSON).
    var verticesData: Data?

    init(name: String,
         width: Int,
         height: Int,
         timestamp: Date = Date(),
         verticesData: Data? = nil)
    {
        self.name = name
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.verticesData = verticesData
    }
}

// MARK: - Extension: loading / saving functions

extension PicExpressDocument {
    /// Loads all polygons from `verticesData`.
    func loadAllPolygons() -> [StoredPolygon] {
        guard let data = verticesData else { return [] }
        do {
            return try JSONDecoder().decode([StoredPolygon].self, from: data)
        } catch {
            print("Error decoding polygons:", error)
            return []
        }
    }

    /// Saves a list of polygons in `verticesData`.
    func saveAllPolygons(_ polygons: [StoredPolygon]) {
        do {
            let data = try JSONEncoder().encode(polygons)
            self.verticesData = data
        } catch {
            print("Error encoding polygons:", error)
        }
    }
}
