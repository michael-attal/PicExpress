//
//  PicExpressDocument.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import Foundation
import SwiftData

/// Represents an encodable 2D point (if needed for older references).
public struct Point2D: Codable, Equatable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

@Model
public final class PicExpressDocument {
    /// Document name
    var name: String

    /// Creation date
    var createdAt: Date = Date()

    /// Last modified date
    var timestamp: Date

    /// The "pixel width" and "pixel height" of our canvas
    var width: Int
    var height: Int

    /// If we want to store the merged mesh as Data:
    /// For example, a JSON with vertices + indices
    var meshData: Data?

    init(
        name: String,
        width: Int,
        height: Int,
        timestamp: Date = Date(),
        meshData: Data? = nil
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.meshData = meshData
    }

    // MARK: - Example: saving/loading the mesh from JSON

    /// Saves a big mesh (vertices + indices) in meshData, to reload later
    public func saveMesh(_ vertices: [PolygonVertex], _ indices: [UInt16]) {
        let container = SavedMesh(vertices: vertices, indices: indices)
        do {
            let encoded = try JSONEncoder().encode(container)
            self.meshData = encoded
        } catch {
            print("Error encoding mesh =>", error)
        }
    }

    public func loadMesh() -> (vertices: [PolygonVertex], indices: [UInt16])? {
        guard let d = meshData else { return nil }
        do {
            let container = try JSONDecoder().decode(SavedMesh.self, from: d)
            return (container.vertices, container.indices)
        } catch {
            print("Error decoding mesh =>", error)
            return nil
        }
    }
}

/// A container structure if you wish to encode the entire big mesh
private struct SavedMesh: Codable {
    let vertices: [PolygonVertex]
    let indices: [UInt16]
}
