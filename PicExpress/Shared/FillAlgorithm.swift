//
//  FillAlgorithm.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

import SwiftUI

/// Enumeration of fill algorithms
public enum FillAlgorithm: String, Identifiable, CaseIterable, Sendable, SelectionItem {
    public var id: String { rawValue }

    case seedRecursive = "Germes (récursif)"
    case seedStack = "Germes (stack)"
    case scanline = "Scanline"
    case lca = "LCA"

    /// Returns the rawValue as the description
    public var description: String { rawValue }
}

/// A utility class containing static methods for polygon fill & pixel fill.
public enum FillAlgorithms {
    /// "Vector fill" – we just set the polygon's color to our new color (ignoring fillAlgo).
    @MainActor
    public static func fillPolygonVector(
        _ polygon: StoredPolygon,
        with fillAlgo: FillAlgorithm,
        color: Color
    ) -> StoredPolygon {
        let floatArr = colorToFloatArray(color)
        let newPoly = StoredPolygon(points: polygon.points, color: floatArr)
        return newPoly
    }

    /// Public method to fill pixels in the CPU buffer, depending on `fillAlgo`.
    /// - Parameters:
    ///   - buffer: The RGBA8 buffer (width*height*4 bytes).
    ///   - width, height: Dimensions of the buffer.
    ///   - startX, startY: The seed point for BFS/DFS/Scanline, or a point inside the polygon for LCA.
    ///   - fillAlgo: Which fill algorithm to use.
    ///   - fillColor: The color used for filling.
    ///   - polygons: (Optional) For LCA, pass the polygon list to find which polygon to fill.
    @MainActor
    public static func fillPixels(
        buffer: inout [UInt8],
        width: Int,
        height: Int,
        startX: Int,
        startY: Int,
        fillAlgo: FillAlgorithm,
        fillColor: Color,
        polygons: [StoredPolygon]? = nil
    ) {
        switch fillAlgo {
        case .seedRecursive:
            print("Filling with seedRecursive algorithm")
            floodFillRecursive(
                &buffer, width, height,
                startX, startY,
                getPixelColor(buffer, width, height, startX, startY),
                colorToByteTuple(fillColor)
            )

        case .seedStack:
            print("Filling with seedStack algorithm")
            floodFillStack(
                &buffer, width, height,
                startX, startY,
                fillColor
            )

        case .scanline:
            print("Filling with scanline algorithm")
            scanlineFill(
                &buffer, width, height,
                startX, startY,
                fillColor
            )

        case .lca:
            print("Filling with LCA algorithm")
            guard let polys = polygons, !polys.isEmpty else {
                print("LCA fill: no polygons => no fill done.")
                return
            }
            // Find polygon (startX,startY)
            for poly in polys {
                if isPointInPolygon(
                    ECTPoint(x: Double(startX), y: Double(startY)),
                    polygon: poly.points
                ) {
                    fillPolygonLCA(
                        polygon: poly,
                        buffer: &buffer,
                        width: width,
                        height: height,
                        fillColor: fillColor
                    )
                    return
                }
            }
            print("LCA fill: no polygon found containing (\(startX),\(startY)). No fill done.")
        }
    }

    // MARK: - (A) Fill by Germes (récursif)

    private static func floodFillRecursive(
        _ buf: inout [UInt8],
        _ w: Int,
        _ h: Int,
        _ x: Int,
        _ y: Int,
        _ targetColor: (UInt8, UInt8, UInt8, UInt8),
        _ newColor: (UInt8, UInt8, UInt8, UInt8)
    ) {
        if x<0||x>=w||y<0||y>=h { return }
        let curr = getPixelColor(buf, w, h, x, y)
        if curr != targetColor { return }
        if curr==newColor { return }

        setPixelColor(&buf, w, h, x, y, newColor)

        floodFillRecursive(&buf, w, h, x+1, y, targetColor, newColor)
        floodFillRecursive(&buf, w, h, x - 1, y, targetColor, newColor)
        floodFillRecursive(&buf, w, h, x, y+1, targetColor, newColor)
        floodFillRecursive(&buf, w, h, x, y - 1, targetColor, newColor)
    }

    // MARK: - (B) Fill by Germes (stack)

    private static func floodFillStack(
        _ buf: inout [UInt8],
        _ w: Int,
        _ h: Int,
        _ sx: Int,
        _ sy: Int,
        _ fillColor: Color
    ) {
        if sx<0||sx>=w||sy<0||sy>=h { return }
        let newColor = colorToByteTuple(fillColor)
        let target = getPixelColor(buf, w, h, sx, sy)
        if target==newColor { return }

        var stack: [(Int, Int)] = []
        stack.append((sx, sy))

        while !stack.isEmpty {
            let (xx, yy) = stack.removeLast()
            if xx<0||xx>=w||yy<0||yy>=h { continue }

            let curr = getPixelColor(buf, w, h, xx, yy)
            if curr==target {
                setPixelColor(&buf, w, h, xx, yy, newColor)
                stack.append((xx+1, yy))
                stack.append((xx - 1, yy))
                stack.append((xx, yy+1))
                stack.append((xx, yy - 1))
            }
        }
    }

    // MARK: - (C) Fill by "Scanline" (seed-based)

    private static func scanlineFill(
        _ buf: inout [UInt8],
        _ w: Int,
        _ h: Int,
        _ sx: Int,
        _ sy: Int,
        _ fillColor: Color
    ) {
        let nc = colorToByteTuple(fillColor)
        let seed = getPixelColor(buf, w, h, sx, sy)
        if seed==nc { return }

        var stack: [(Int, Int)] = []
        stack.append((sx, sy))

        while !stack.isEmpty {
            let (startX, startY) = stack.removeLast()
            if startY<0||startY>=h { continue }

            // Move left
            var left = startX
            while left>=0, getPixelColor(buf, w, h, left, startY)==seed {
                left -= 1
            }

            // Move right
            var right = startX
            while right<w, getPixelColor(buf, w, h, right, startY)==seed {
                right += 1
            }

            let x1 = left+1
            let x2 = right - 1
            if x1<=x2 {
                // fill the row
                for x in x1...x2 {
                    setPixelColor(&buf, w, h, x, startY, nc)
                }
            }

            // check the line above & below
            if x1<=x2 {
                // above
                let rowAbove = startY - 1
                if rowAbove>=0 {
                    var x = x1
                    while x<=x2 {
                        let cUp = getPixelColor(buf, w, h, x, rowAbove)
                        if cUp==seed {
                            stack.append((x, rowAbove))
                            while x<=x2, getPixelColor(buf, w, h, x, rowAbove)==seed {
                                x += 1
                            }
                        }
                        x += 1
                    }
                }
                // below
                let rowBelow = startY+1
                if rowBelow<h {
                    var x = x1
                    while x<=x2 {
                        let cDn = getPixelColor(buf, w, h, x, rowBelow)
                        if cDn==seed {
                            stack.append((x, rowBelow))
                            while x<=x2, getPixelColor(buf, w, h, x, rowBelow)==seed {
                                x += 1
                            }
                        }
                        x += 1
                    }
                }
            }
        }
    }

    // MARK: - (D) Fill by LCA (Liste des Côtés Actifs) - polygon-based

    private static func fillPolygonLCA(
        polygon: StoredPolygon,
        buffer: inout [UInt8],
        width: Int,
        height: Int,
        fillColor: Color
    ) {
        let pts = polygon.points
        guard pts.count>=3 else { return }

        // Find yMin, yMax
        var yMin = Int.max
        var yMax = Int.min
        for p in pts {
            let iy = Int(floor(p.y))
            if iy<yMin { yMin = iy }
            if iy>yMax { yMax = iy }
        }
        // Clipper aux bornes
        yMin = max(yMin, 0)
        yMax = min(yMax, height - 1)
        if yMin>yMax { return }

        // Builds edge list
        var edges: [EdgeData] = []
        for i in 0..<pts.count {
            let j = (i+1) % pts.count
            var x1 = pts[i].x, y1 = pts[i].y
            var x2 = pts[j].x, y2 = pts[j].y
            if y2<y1 {
                swap(&x1, &x2)
                swap(&y1, &y2)
            }
            if Int(y1)==Int(y2) {
                // horizontal => ignore
                continue
            }
            let dx = x2 - x1
            let dy = y2 - y1
            let invSlope = dx / dy
            edges.append(EdgeData(xMin: x1, yMin: y1, yMax: y2, invSlope: invSlope))
        }

        let fillByteColor = colorToByteTuple(fillColor)
        for scanY in yMin...yMax {
            var xIntersects: [Double] = []
            for e in edges {
                if Double(scanY)>=e.yMin, Double(scanY)<e.yMax {
                    let x = e.xMin+(Double(scanY) - e.yMin)*e.invSlope
                    xIntersects.append(x)
                }
            }
            if xIntersects.isEmpty { continue }
            xIntersects.sort()
            var i = 0
            while i<xIntersects.count - 1 {
                let x1 = Int(ceil(xIntersects[i]))
                let x2 = Int(floor(xIntersects[i+1]))
                if x1<=x2 {
                    for x in x1...x2 {
                        if x>=0, x<width {
                            setPixelColor(&buffer, width, height, x, scanY, fillByteColor)
                        }
                    }
                }
                i += 2
            }
        }
    }

    // MARK: - isPointInPolygon (for LCA usage)

    private static func isPointInPolygon(
        _ p: ECTPoint,
        polygon: [Point2D]
    ) -> Bool {
        let x = p.x
        let y = p.y
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y

            let intersect = ((yi>y) != (yj>y)) &&
                (x<(xj - xi)*(y - yi) / (yj - yi)+xi)
            if intersect {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: - Internal structures & utils

    fileprivate struct EdgeData {
        let xMin: Double
        let yMin: Double
        let yMax: Double
        let invSlope: Double
    }

    private static func colorToByteTuple(_ color: Color) -> (UInt8, UInt8, UInt8, UInt8) {
        // Sur macOS, on peut convertir Color -> NSColor
        let cgColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        cgColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (
            UInt8(clamping: Int(r*255)),
            UInt8(clamping: Int(g*255)),
            UInt8(clamping: Int(b*255)),
            UInt8(clamping: Int(a*255))
        )
    }

    private static func colorToFloatArray(_ color: Color) -> [Float] {
        let cgColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        cgColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Float(r), Float(g), Float(b), Float(a)]
    }

    private static func getPixelColor(
        _ buf: [UInt8],
        _ w: Int,
        _ h: Int,
        _ x: Int,
        _ y: Int
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        let idx = (y*w+x)*4
        return (buf[idx+0], buf[idx+1], buf[idx+2], buf[idx+3])
    }

    private static func setPixelColor(
        _ buf: inout [UInt8],
        _ w: Int,
        _ h: Int,
        _ x: Int,
        _ y: Int,
        _ c: (UInt8, UInt8, UInt8, UInt8)
    ) {
        let idx = (y*w+x)*4
        buf[idx+0] = c.0
        buf[idx+1] = c.1
        buf[idx+2] = c.2
        buf[idx+3] = c.3
    }
}
