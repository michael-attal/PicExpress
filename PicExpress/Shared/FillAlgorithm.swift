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
    case gpuFragment = "GPU Fill"
    case defaultPipelineGPU = "GPU Default Pipeline"

    public var description: String { rawValue }
}

/// We define two fill rules: .evenOdd (even-odd) and .winding
public enum FillRule: String, Identifiable, CaseIterable, Sendable, SelectionItem {
    public var id: String { rawValue }

    case evenOdd = "Even-Odd"
    case winding = "Winding"
    // case both = "Even-Odd and Winding" // TODO: IMPLEMENT IT

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
        let newPoly = StoredPolygon(
            points: polygon.points,
            color: floatArr,
            polygonTextureData: polygon.polygonTextureData,
            textureWidth: polygon.textureWidth,
            textureHeight: polygon.textureHeight
        )
        return newPoly
    }

    // -------------------------------------------------------------------

    // MARK: - 2) fillPixels => main entry

    // -------------------------------------------------------------------
    /**
      fillPixels(...) :
        - identifies the polygon clicked (the one containing startX, startY)
        - retrieves the “originalColor” color under the pixel
        - searches for all polygons of the same color => “allowedPolygons”.
        - according to fillAlgo :
           .lca => fillPolygonLCA => colors only the clicked polygon
           .seedRecursive / .seedStack / .scanline => flood fill color-based,
             ignores any pixel that does not belong to an “allowedPolygon”.

      NB: .gpuFragment => no CPU fill
     */
    @MainActor
    public static func fillPixels(
        buffer: inout [UInt8],
        width: Int,
        height: Int,
        startX: Int,
        startY: Int,
        fillAlgo: FillAlgorithm,
        fillColor: Color,
        polygons: [StoredPolygon]? = nil,
        fillRule: FillRule = .evenOdd
    ) {
        // 1) .gpuFragment => nothing
        if fillAlgo == .gpuFragment {
            return
        }

        guard let polys = polygons, !polys.isEmpty else {
            return
        }

        // 2) find the clicked polygon
        var clickedPolyIndex: Int?
        for i in 0..<polys.count {
            if isPointInPolygon(ECTPoint(x: Double(startX), y: Double(startY)),
                                polygon: polys[i].points,
                                fillRule: fillRule)
            {
                clickedPolyIndex = i
                break
            }
        }
        guard let cIndex = clickedPolyIndex else {
            // no polygon found => no fill
            return
        }

        let clickedPoly = polys[cIndex]

        // 3) If it is .lca => fillPolygonLCA (colors ONLY the clicked polygon)
        if fillAlgo == .lca {
            fillPolygonLCA(
                polygon: clickedPoly,
                buffer: &buffer,
                width: width,
                height: height,
                fillColor: fillColor,
                allPolygons: polys, // if we want to exclude overlaps with other colors
                fillRule: fillRule
            )
            return
        }

        // 4) Otherwise => “color-based fill” => seedRecursive, seedStack, scanline
        // Retrieve the “originalColor” of the pixel
        let originalColor = getPixelColor(buffer, width, height, startX, startY)
        let newColor = colorToByteTuple(fillColor)
        if originalColor == newColor {
            return
        }

        // Identify all polygons that have the same “RGBA color” as the clicked polygon
        // => only color the pixels that belong to at least one of these polygons
        let polyColor = clickedPoly.color
        let allowedPolygons = polys.filter { $0.color == polyColor }

        switch fillAlgo {
        case .seedRecursive:
            seedRecursiveFill(
                &buffer,
                width,
                height,
                startX,
                startY,
                originalColor,
                newColor,
                allowedPolygons,
                fillRule
            )
        case .seedStack:
            seedStackFill(
                &buffer,
                width,
                height,
                startX,
                startY,
                originalColor,
                newColor,
                allowedPolygons,
                fillRule
            )
        case .scanline:
            scanlineFill(
                &buffer,
                width,
                height,
                startX,
                startY,
                originalColor,
                newColor,
                allowedPolygons,
                fillRule
            )
        default:
            break
        }
    }

    // -------------------------------------------------------------------

    // MARK: - 3) LCA => polygon-based fill

    // -------------------------------------------------------------------
    /**
      fillPolygonLCA => only fills the given polygon (list of active edges).
      Excludes any pixel that is overlapping with other polygons of different colors.
      => if we want to ignore an overlapping polygon of the same color => we need to change the condition, etc.
     */
    private static func fillPolygonLCA(
        polygon: StoredPolygon,
        buffer: inout [UInt8],
        width: Int,
        height: Int,
        fillColor: Color,
        allPolygons: [StoredPolygon],
        fillRule: FillRule
    ) {
        let pts = polygon.points
        if pts.count < 3 { return }

        // bounding
        var yMin = Int.max
        var yMax = Int.min
        for p in pts {
            let iy = Int(floor(p.y))
            if iy < yMin { yMin = iy }
            if iy > yMax { yMax = iy }
        }
        yMin = max(yMin, 0)
        yMax = min(yMax, height - 1)
        if yMin > yMax { return }

        // build edges
        var edges: [EdgeData] = []
        edges.reserveCapacity(pts.count)

        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            var x1 = Float(pts[i].x)
            var y1 = Float(pts[i].y)
            var x2 = Float(pts[j].x)
            var y2 = Float(pts[j].y)
            if y2 < y1 {
                swap(&x1, &x2)
                swap(&y1, &y2)
            }
            if abs(y2 - y1) < 1e-6 { continue }
            let dx = x2 - x1
            let dy = y2 - y1
            let invSlope = dx / dy
            edges.append(EdgeData(xMin: x1, yMin: y1, yMax: y2, invSlope: invSlope))
        }

        let fillCol = colorToByteTuple(fillColor)

        for scanY in yMin...yMax {
            var xIntersects: [Float] = []
            for e in edges {
                if Float(scanY) >= e.yMin, Float(scanY) < e.yMax {
                    let xx = e.xMin + (Float(scanY) - e.yMin) * e.invSlope
                    xIntersects.append(xx)
                }
            }
            if xIntersects.isEmpty { continue }
            xIntersects.sort()

            var i = 0
            while i < xIntersects.count - 1 {
                let x1 = Int(ceil(xIntersects[i]))
                let x2 = Int(floor(xIntersects[i + 1]))
                if x1 <= x2 {
                    for x in x1...x2 {
                        if x >= 0, x < width {
                            // Check if the pixel is in “allPolygons” overlapping => you can exclude if another poly has a different color
                            // In this example, exclude any other polygon => Only color if pixel ∈ this polygon + not in any other different poly
                            let pTest = ECTPoint(x: Double(x), y: Double(scanY))
                            var belongsToAnotherDifferentColor = false
                            for otherPoly in allPolygons {
                                if otherPoly.points == polygon.points {
                                    continue
                                }
                                if isPointInPolygon(pTest, polygon: otherPoly.points, fillRule: fillRule) {
                                    // => overlap => if color is different => do not color
                                    if otherPoly.color != polygon.color {
                                        belongsToAnotherDifferentColor = true
                                        break
                                    }
                                }
                            }
                            if !belongsToAnotherDifferentColor {
                                setPixelColor(&buffer, width, height, x, scanY, fillCol)
                            }
                        }
                    }
                }
                i += 2
            }
        }
    }

    // -------------------------------------------------------------------

    // MARK: - 4) Color-based algorithms: seedRecursive, seedStack, scanline

    // -------------------------------------------------------------------
    /**
      Each of these algorithms (A, B, C) performs a classic “bucket fill”
      (we check the target color, colorize, propagate),
      **but** we add a test “does this pixel belong to at least one polygon among ‘allowedPolygons’?”
     */

    // (A) seedRecursive => DFS recursive
    private static func seedRecursiveFill(
        _ buf: inout [UInt8],
        _ w: Int,
        _ h: Int,
        _ x: Int,
        _ y: Int,
        _ targetColor: (UInt8, UInt8, UInt8, UInt8),
        _ newColor: (UInt8, UInt8, UInt8, UInt8),
        _ allowedPolygons: [StoredPolygon],
        _ fillRule: FillRule
    ) {
        // outside image
        if x < 0 || x >= w || y < 0 || y >= h { return }

        let curr = getPixelColor(buf, w, h, x, y)
        // check color
        if curr != targetColor { return }
        // check allowed polygons
        if !pixelIsInAllowedPolygons(x, y, allowedPolygons, fillRule) { return }

        // colorize
        setPixelColor(&buf, w, h, x, y, newColor)

        // propagate
        seedRecursiveFill(&buf, w, h, x + 1, y, targetColor, newColor, allowedPolygons, fillRule)
        seedRecursiveFill(&buf, w, h, x - 1, y, targetColor, newColor, allowedPolygons, fillRule)
        seedRecursiveFill(&buf, w, h, x, y + 1, targetColor, newColor, allowedPolygons, fillRule)
        seedRecursiveFill(&buf, w, h, x, y - 1, targetColor, newColor, allowedPolygons, fillRule)
    }

    // (B) seedStack => DFS iterative
    private static func seedStackFill(
        _ buf: inout [UInt8],
        _ w: Int,
        _ h: Int,
        _ sx: Int,
        _ sy: Int,
        _ targetColor: (UInt8, UInt8, UInt8, UInt8),
        _ newColor: (UInt8, UInt8, UInt8, UInt8),
        _ allowedPolygons: [StoredPolygon],
        _ fillRule: FillRule
    ) {
        var stack = [(sx, sy)]
        while !stack.isEmpty {
            let (xx, yy) = stack.removeLast()
            if xx < 0 || xx >= w || yy < 0 || yy >= h { continue }

            let curr = getPixelColor(buf, w, h, xx, yy)
            if curr == targetColor,
               pixelIsInAllowedPolygons(xx, yy, allowedPolygons, fillRule)
            {
                setPixelColor(&buf, w, h, xx, yy, newColor)
                stack.append((xx + 1, yy))
                stack.append((xx - 1, yy))
                stack.append((xx, yy + 1))
                stack.append((xx, yy - 1))
            }
        }
    }

    // (C) scanline => fill in horizontal segments
    private static func scanlineFill(
        _ buf: inout [UInt8],
        _ w: Int,
        _ h: Int,
        _ sx: Int,
        _ sy: Int,
        _ targetColor: (UInt8, UInt8, UInt8, UInt8),
        _ newColor: (UInt8, UInt8, UInt8, UInt8),
        _ allowedPolygons: [StoredPolygon],
        _ fillRule: FillRule
    ) {
        var stack = [(sx, sy)]
        while !stack.isEmpty {
            let (startX, startY) = stack.removeLast()
            if startY < 0 || startY >= h { continue }

            // move left
            var left = startX
            while left >= 0,
                  getPixelColor(buf, w, h, left, startY) == targetColor,
                  pixelIsInAllowedPolygons(left, startY, allowedPolygons, fillRule)
            {
                left -= 1
            }

            // move right
            var right = startX
            while right < w,
                  getPixelColor(buf, w, h, right, startY) == targetColor,
                  pixelIsInAllowedPolygons(right, startY, allowedPolygons, fillRule)
            {
                right += 1
            }

            let x1 = left + 1
            let x2 = right - 1
            if x1 <= x2 {
                // color the line
                for x in x1...x2 {
                    setPixelColor(&buf, w, h, x, startY, newColor)
                }

                // above line
                let rowUp = startY - 1
                if rowUp >= 0 {
                    var x = x1
                    while x <= x2 {
                        if getPixelColor(buf, w, h, x, rowUp) == targetColor,
                           pixelIsInAllowedPolygons(x, rowUp, allowedPolygons, fillRule)
                        {
                            stack.append((x, rowUp))
                            // skip the segment
                            while x <= x2,
                                  getPixelColor(buf, w, h, x, rowUp) == targetColor,
                                  pixelIsInAllowedPolygons(x, rowUp, allowedPolygons, fillRule)
                            {
                                x += 1
                            }
                        }
                        x += 1
                    }
                }

                // below line
                let rowDn = startY + 1
                if rowDn < h {
                    var x = x1
                    while x <= x2 {
                        if getPixelColor(buf, w, h, x, rowDn) == targetColor,
                           pixelIsInAllowedPolygons(x, rowDn, allowedPolygons, fillRule)
                        {
                            stack.append((x, rowDn))
                            while x <= x2,
                                  getPixelColor(buf, w, h, x, rowDn) == targetColor,
                                  pixelIsInAllowedPolygons(x, rowDn, allowedPolygons, fillRule)
                            {
                                x += 1
                            }
                        }
                        x += 1
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------

    // MARK: - Helpers

    // -------------------------------------------------------------------
    /**
      pixelIsInAllowedPolygons(x, y, allowedPolygons) => true if (x, y)
      belongs to AT LEAST one polygon of “allowedPolygons”.
     */
    private static func pixelIsInAllowedPolygons(
        _ x: Int,
        _ y: Int,
        _ allowedPolygons: [StoredPolygon],
        _ fillRule: FillRule
    ) -> Bool {
        let pt = ECTPoint(x: Double(x), y: Double(y))
        for poly in allowedPolygons {
            if isPointInPolygon(pt, polygon: poly.points, fillRule: fillRule) {
                return true
            }
        }
        return false
    }

    /**
      isPointInPolygon => returns true if “pt” is in “polygon”
      according to the fillRule (evenOdd or winding).
     */
    public static func isPointInPolygon(
        _ pt: ECTPoint,
        polygon: [Point2D],
        fillRule: FillRule
    ) -> Bool {
        switch fillRule {
        case .evenOdd:
            return isPointInPolygonEvenOdd(pt, polygon)
        case .winding:
            return isPointInPolygonWinding(pt, polygon)
        }
    }

    // even-odd
    private static func isPointInPolygonEvenOdd(
        _ pt: ECTPoint,
        _ polygon: [Point2D]
    ) -> Bool {
        let x = pt.x; let y = pt.y
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y

            let intersect = ((yi > y) != (yj > y))
                && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            if intersect {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // winding
    private static func isPointInPolygonWinding(
        _ pt: ECTPoint,
        _ polygon: [Point2D]
    ) -> Bool {
        var windingNumber = 0
        let n = polygon.count
        for i in 0..<n {
            let j = (i + 1) % n
            let p1 = polygon[i]
            let p2 = polygon[j]
            if p1.y <= pt.y {
                if (p2.y > pt.y) && (isLeftEdge(p1, p2, pt) > 0) {
                    windingNumber += 1
                }
            } else {
                if (p2.y <= pt.y) && (isLeftEdge(p1, p2, pt) < 0) {
                    windingNumber -= 1
                }
            }
        }
        return windingNumber != 0
    }

    private static func isLeftEdge(_ A: Point2D, _ B: Point2D, _ P: ECTPoint) -> Double {
        return (B.x - A.x) * (P.y - A.y) - (B.y - A.y) * (P.x - A.x)
    }

    // ----------------------------------------------
    // Low-level color buffer helpers
    // ----------------------------------------------
    public static func getPixelColor(
        _ buf: [UInt8],
        _ w: Int,
        _ h: Int,
        _ x: Int,
        _ y: Int
    ) -> (UInt8, UInt8, UInt8, UInt8) {
        let idx = (y * w + x) * 4
        return (buf[idx + 0], buf[idx + 1], buf[idx + 2], buf[idx + 3])
    }

    public static func setPixelColor(
        _ buf: inout [UInt8],
        _ w: Int,
        _ h: Int,
        _ x: Int,
        _ y: Int,
        _ c: (UInt8, UInt8, UInt8, UInt8)
    ) {
        let idx = (y * w + x) * 4
        buf[idx + 0] = c.0
        buf[idx + 1] = c.1
        buf[idx + 2] = c.2
        buf[idx + 3] = c.3
    }

    // convert SwiftUI.Color -> float array
    public static func colorToFloatArray(_ color: Color) -> [Float] {
        let cg = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        cg.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [Float(r), Float(g), Float(b), Float(a)]
    }

    // convert SwiftUI.Color -> (UInt8,UInt8,UInt8,UInt8)
    public static func colorToByteTuple(_ color: Color) -> (UInt8, UInt8, UInt8, UInt8) {
        let cg = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        cg.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), UInt8(a * 255))
    }

    // -------------------------------------------------------------------

    // MARK: - EdgeData for LCA

    // -------------------------------------------------------------------
    fileprivate struct EdgeData {
        let xMin: Float
        let yMin: Float
        let yMax: Float
        let invSlope: Float
    }
}
