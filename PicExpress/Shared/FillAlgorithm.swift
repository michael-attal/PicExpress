//
//  FillAlgorithm.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

import Foundation
import SwiftUI

/// Enumeration of fill algorithms
enum FillAlgorithm: String, Identifiable, CaseIterable, Sendable {
    var id: String { rawValue }

    case seedRecursive = "Germes (récursif)"
    case seedStack = "Germes (stack)"
    case scanline = "Scanline"
    case lca = "LCA"
}

// MARK: - Utility

private func colorToFloatArray(_ color: Color) -> [Float] {
    let cgColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    cgColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    return [Float(r), Float(g), Float(b), Float(a)]
}

private func colorToByteTuple(_ color: Color) -> (UInt8, UInt8, UInt8, UInt8) {
    let f = colorToFloatArray(color)
    return (UInt8(f[0]*255), UInt8(f[1]*255), UInt8(f[2]*255), UInt8(f[3]*255))
}

/// Utility class for fill algorithms
@MainActor
final class FillAlgorithms {
    /// Just sets the color (vector fill)
    static func fillPolygonVector(_ polygon: StoredPolygon,
                                  with fillAlgo: FillAlgorithm,
                                  color: Color) -> StoredPolygon
    {
        let newC = colorToFloatArray(color)
        let newPoly = StoredPolygon(points: polygon.points, color: newC)
        return newPoly
    }

    /// Pixel-based fill
    static func fillPixels(buffer: inout [UInt8],
                           width: Int,
                           height: Int,
                           startX: Int,
                           startY: Int,
                           fillAlgo: FillAlgorithm,
                           fillColor: Color)
    {
        switch fillAlgo {
        case .seedRecursive:
            floodFillRecursive(&buffer, width, height,
                               startX, startY,
                               getPixelColor(buffer, width, height, startX, startY),
                               colorToByteTuple(fillColor))
        case .seedStack:
            floodFillStack(&buffer, width, height,
                           startX, startY,
                           fillColor)
        case .scanline:
            scanlineFill(&buffer, width, height,
                         startX, startY,
                         fillColor)
        case .lca:
            fillLCAstub(&buffer, width, height,
                        startX, startY,
                        fillColor)
        }
    }

    // MARK: - (a) recursive

    private static func floodFillRecursive(_ buf: inout [UInt8],
                                           _ w: Int,
                                           _ h: Int,
                                           _ x: Int,
                                           _ y: Int,
                                           _ targetColor: (UInt8, UInt8, UInt8, UInt8),
                                           _ newColor: (UInt8, UInt8, UInt8, UInt8))
    {
        if x<0||x>=w||y<0||y>=h { return }
        let curr = getPixelColor(buf, w, h, x, y)
        if curr != targetColor { return }
        if curr==newColor { return }

        setPixelColor(&buf, w, h, x, y, newColor)
        floodFillRecursive(&buf, w, h, x+1, y, targetColor, newColor)
        floodFillRecursive(&buf, w, h, x-1, y, targetColor, newColor)
        floodFillRecursive(&buf, w, h, x, y+1, targetColor, newColor)
        floodFillRecursive(&buf, w, h, x, y-1, targetColor, newColor)
    }

    // MARK: - (b) seed stack

    private static func floodFillStack(_ buf: inout [UInt8],
                                       _ w: Int,
                                       _ h: Int,
                                       _ startX: Int,
                                       _ startY: Int,
                                       _ fillColor: Color)
    {
        if startX<0||startX>=w||startY<0||startY>=h { return }
        let newColor = colorToByteTuple(fillColor)
        let target = getPixelColor(buf, w, h, startX, startY)
        if target==newColor { return }

        var stack: [(Int, Int)] = []
        stack.append((startX, startY))

        while !stack.isEmpty {
            let (xx, yy) = stack.removeLast()
            if xx<0||xx>=w||yy<0||yy>=h { continue }

            let curr = getPixelColor(buf, w, h, xx, yy)
            if curr==target {
                setPixelColor(&buf, w, h, xx, yy, newColor)
                stack.append((xx+1, yy))
                stack.append((xx-1, yy))
                stack.append((xx, yy+1))
                stack.append((xx, yy-1))
            }
        }
    }

    // MARK: - (c) scanline

    private static func scanlineFill(_ buf: inout [UInt8],
                                     _ w: Int,
                                     _ h: Int,
                                     _ sx: Int,
                                     _ sy: Int,
                                     _ fillColor: Color)
    {
        let nc = colorToByteTuple(fillColor)
        let target = getPixelColor(buf, w, h, sx, sy)
        if target==nc { return }

        var stack: [(Int, Int)] = []
        stack.append((sx, sy))

        while !stack.isEmpty {
            let (startX, startY) = stack.removeLast()
            if startY<0||startY>=h { continue }

            // Move left
            var left = startX
            while left>=0, getPixelColor(buf, w, h, left, startY)==target {
                left -= 1
            }
            // Move right
            var right = startX
            while right<w, getPixelColor(buf, w, h, right, startY)==target {
                right += 1
            }

            let x1 = left+1
            let x2 = right-1

            if x1<=x2 {
                // fill
                for x in x1...x2 {
                    setPixelColor(&buf, w, h, x, startY, nc)
                }
            }

            // check lines above/below
            if x1<=x2 {
                for x in x1...x2 {
                    if startY > 0 {
                        let cUp = getPixelColor(buf, w, h, x, startY-1)
                        if cUp==target { stack.append((x, startY-1)) }
                    }
                    if startY<(h-1) {
                        let cDn = getPixelColor(buf, w, h, x, startY+1)
                        if cDn==target { stack.append((x, startY+1)) }
                    }
                }
            }
        }
    }

    // MARK: - (d) LCA stub

    private static func fillLCAstub(_ buf: inout [UInt8],
                                    _ w: Int,
                                    _ h: Int,
                                    _ sx: Int,
                                    _ sy: Int,
                                    _ fillColor: Color)
    {
        print("LCA fill not fully implemented, fallback BFS.")
        floodFillStack(&buf, w, h, sx, sy, fillColor)
    }

    // MARK: - get/set pixel

    private static func getPixelColor(_ buf: [UInt8],
                                      _ w: Int,
                                      _ h: Int,
                                      _ x: Int,
                                      _ y: Int) -> (UInt8, UInt8, UInt8, UInt8)
    {
        let idx = (y*w+x)*4
        return (buf[idx+0], buf[idx+1], buf[idx+2], buf[idx+3])
    }

    private static func setPixelColor(_ buf: inout [UInt8],
                                      _ w: Int,
                                      _ h: Int,
                                      _ x: Int,
                                      _ y: Int,
                                      _ c: (UInt8, UInt8, UInt8, UInt8))
    {
        let idx = (y*w+x)*4
        buf[idx+0] = c.0
        buf[idx+1] = c.1
        buf[idx+2] = c.2
        buf[idx+3] = c.3
    }
}
