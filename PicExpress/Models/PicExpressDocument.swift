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
    /// Document or project name
    var name: String

    /// Date created or last modified
    var timestamp: Date

    /// Binary storage of our polygons. We use a [StoredPolygon] array encoded/decoded in JSON to load polygon into metal canvas later
    var verticesData: Data?

    // MARK: - Init

    init(name: String, timestamp: Date = Date(), verticesData: Data? = nil) {
        self.name = name
        self.timestamp = timestamp
        self.verticesData = verticesData
    }
}

// MARK: - Extension: loading / saving functions

extension PicExpressDocument {
    /// Loads the complete list of polygons stored in `verticesData`.
    /// Returns [] if there is nothing or if deserialization fails.
    func loadAllPolygons() -> [StoredPolygon] {
        guard let data = verticesData else { return [] }
        do {
            return try JSONDecoder().decode([StoredPolygon].self, from: data)
        } catch {
            print("Error decoding polygons:", error)
            return []
        }
    }

    /// Saves a complete list of polygons in `verticesData`.
    func saveAllPolygons(_ polygons: [StoredPolygon]) {
        do {
            let data = try JSONEncoder().encode(polygons)
            self.verticesData = data
        } catch {
            print("Error encoding polygons:", error)
        }
    }
}
