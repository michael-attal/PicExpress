//
//  PicExpressDocument.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import AppKit
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

    var fillTexturePNG: Data?

    init(
        name: String,
        width: Int,
        height: Int,
        timestamp: Date = Date(),
        meshData: Data? = nil,
        fillTexture: Data? = nil
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.meshData = meshData
        self.fillTexturePNG = fillTexture
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

    public func saveFillTexture(_ buffer: [UInt8], width: Int, height: Int) {
        guard let cgImage = Utils.makeCGImageRGBA8(
            from: buffer,
            width: width,
            height: height
        ) else {
            return
        }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        guard let tiffData = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:])
        else {
            return
        }
        self.fillTexturePNG = pngData
        print("Doc => fillTexturePNG updated.")
    }

    public func loadFillTexture() -> [UInt8]? {
        guard let pngData = self.fillTexturePNG else {
            return nil
        }
        guard let nsImage = NSImage(data: pngData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            print("Error decoding fillTexturePNG => no cgImage")
            return nil
        }
        let w = cgImage.width
        let h = cgImage.height
        var buf = [UInt8](repeating: 0, count: w*h*4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &buf,
                                  width: w,
                                  height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: w*4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }
}

/// A container structure if we wish to encode the entire big mesh
private struct SavedMesh: Codable {
    let vertices: [PolygonVertex]
    let indices: [UInt16]
}

extension PicExpressDocument {
    /// Creates a duplicate of the current document with a new unique ID and a modified name.
    func duplicate() -> PicExpressDocument {
        return PicExpressDocument(
            name: "\(self.name) (copie)",
            width: self.width,
            height: self.height,
            timestamp: Date(),
            meshData: self.meshData,
            fillTexture: self.fillTexturePNG
        )
    }
}
