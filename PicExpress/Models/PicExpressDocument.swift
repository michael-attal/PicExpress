//
//  PicExpressDocument.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import Foundation
import SwiftData

/// Represents an encodable 2D point
public struct Point2D: Codable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Represents a stored polygon: list of points + RGBA color
/// NEW: We add the optional texture data for multi-color fill inside the same polygon.
public struct StoredPolygon: Codable {
    public let points: [Point2D]
    public let color: [Float] // (r, g, b, a)

    // NEW properties for storing a doc-size texture specifically for this polygon
    public var polygonTextureData: Data?
    public var textureWidth: Int?
    public var textureHeight: Int?

    public init(
        points: [Point2D],
        color: [Float],
        polygonTextureData: Data? = nil,
        textureWidth: Int? = nil,
        textureHeight: Int? = nil
    ) {
        self.points = points
        self.color = color
        self.polygonTextureData = polygonTextureData
        self.textureWidth = textureWidth
        self.textureHeight = textureHeight
    }
}

@Model
public final class PicExpressDocument {
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

    /// store if the doc is in "merged" mode
    var mergePolygons: Bool = false

    /// We keep a backup of the original polygons so we can restore them
    var backupOriginalPolygonsData: Data?

    init(
        name: String,
        width: Int,
        height: Int,
        timestamp: Date = Date(),
        verticesData: Data? = nil
    ) {
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
            verticesData = data
        } catch {
            print("Error encoding polygons:", error)
        }
    }
}

extension PicExpressDocument {
    /// Sauvegarde d'abord tous les polygones, puis construit UN StoredPolygon
    /// qui contient l'ensembles des triangles de tous les polygones (ear clipping).
    /// => "fusion" en un bloc multi-triangles.
    func makeMultiPolygonEarClipAll() {
        let original = loadAllPolygons()
        if original.isEmpty { return }

        // 1) On garde en backup si pas déjà fait.
        //    (S'il est déjà set, on suppose que c'est déjà fusionné.)
        if backupOriginalPolygonsData == nil {
            backupOriginalPolygonsData = verticesData
        }

        // On choisit la couleur du premier polygone, ou un color par défaut
        let finalColor = original[0].color

        // L'earClip pour trianguler
        let earClip = EarClippingTriangulation()

        // On va accumuler les triangles (3 sommets par triangle) dans un grand tableau
        var megaPoints: [ECTPoint] = []

        for sp in original {
            // On convertit le StoredPolygon en ECTPolygon
            let ectPoints = sp.points.map { ECTPoint(x: $0.x, y: $0.y) }
            let ectPoly = ECTPolygon(vertices: ectPoints)
            // Triangulation ear clipping
            let triangles = earClip.getEarClipTriangles(polygon: ectPoly)
            // On accumule ces sommets
            for tri in triangles {
                megaPoints.append(tri.a)
                megaPoints.append(tri.b)
                megaPoints.append(tri.c)
            }
        }

        if megaPoints.isEmpty {
            // Pas de triangles => on ne fait rien
            return
        }

        // On construit le “super-polygone”
        let finalPts = megaPoints.map { Point2D(x: $0.x, y: $0.y) }
        let multiPoly = StoredPolygon(
            points: finalPts,
            color: finalColor,
            polygonTextureData: nil,
            textureWidth: nil,
            textureHeight: nil
        )

        // On remplace la liste par ce seul “big” polygone
        saveAllPolygons([multiPoly])
    }

    /// Restaure les polygones originaux si on a un backup
    func unmergePolygons() {
        if let backup = backupOriginalPolygonsData {
            // on restaure
            verticesData = backup
            backupOriginalPolygonsData = nil
        }
    }
}
