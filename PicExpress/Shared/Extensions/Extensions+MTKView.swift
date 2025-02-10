//
//  Extensions+MTKView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/02/2025.
//

import AppKit
import MetalKit

// MARK: - Export PNG for macOS

extension MTKView {
    /// Export the current view content to a PNG file at `saveURL`.
    /// We must ensure `self.framebufferOnly = false` before calling `draw()`, and it's bad for performance.
    func exportToPNG(saveURL: URL) {
        // Force creation of currentDrawable if needed
        // This ensures currentDrawable is up to date
        self.draw()

        guard let currentDrawable = self.currentDrawable else {
            print("No currentDrawable available.")
            return
        }

        // Retrieve the drawable texture (must not be framebufferOnly)
        let texture = currentDrawable.texture
        let width = texture.width
        let height = texture.height

        // If the texture is still framebufferOnly => error
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var imageBytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        let region = MTLRegionMake2D(0, 0, width, height)

        // Read back the BGRA bytes
        texture.getBytes(&imageBytes,
                         bytesPerRow: bytesPerRow,
                         from: region,
                         mipmapLevel: 0)

        // Convert BGRA -> RGBA if needed
        for row in 0..<height {
            for col in 0..<width {
                let index = row * bytesPerRow + col * bytesPerPixel
                let b = imageBytes[index + 0]
                let g = imageBytes[index + 1]
                let r = imageBytes[index + 2]
                let a = imageBytes[index + 3]
                // rearrange to RGBA
                imageBytes[index + 0] = r
                imageBytes[index + 1] = g
                imageBytes[index + 2] = b
                imageBytes[index + 3] = a
            }
        }

        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &imageBytes,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let cgImage = context.makeImage()
        else {
            print("Failed to create CGContext or CGImage.")
            return
        }

        // Convert CGImage -> NSImage
        let image = NSImage(cgImage: cgImage,
                            size: NSSize(width: width, height: height))

        // Save as PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            print("Failed to convert image to PNG data.")
            return
        }

        do {
            try pngData.write(to: saveURL)
            print("Exported to PNG:", saveURL.path)
        } catch {
            print("Error writing PNG:", error)
        }
    }
}
