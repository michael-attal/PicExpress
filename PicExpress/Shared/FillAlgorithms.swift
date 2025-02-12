//
//  FillAlgorithms.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

import SwiftUI

/// Enumeration of fill algorithms
public enum AvailableFillAlgorithm: String, Identifiable, CaseIterable, Sendable, SelectionItem {
    public var id: String { rawValue }

    case seedRecursive = "Germes (récursif)"
    case seedStack = "Germes (stack)"
    case scanline = "Scanline"
    case lca = "LCA"

    public var description: String { rawValue }
}

/// We define two fill rules: .evenOdd (even-odd) and .winding
public enum FillRule: String, Identifiable, CaseIterable, Sendable, SelectionItem {
    public var id: String { rawValue }

    case evenOdd = "Even-Odd"
    case winding = "Winding"
    case both = "Even-Odd and Winding"

    public var description: String { rawValue }
}

public struct IntPoint {
    public let x: Int
    public let y: Int
    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

public enum FillAlgorithms {
    // MARK: - 1) Seed fill (recursive)

    public static func seedFillRecursive(
        _ pixels: inout [UInt8],
        _ width: Int,
        _ height: Int,
        _ startX: Int,
        _ startY: Int,
        _ targetColor: (UInt8, UInt8, UInt8, UInt8),
        _ fillColor: (UInt8, UInt8, UInt8, UInt8)
    ) {
        print("[seedFillRecursive] start from (\(startX), \(startY)), targetColor=\(targetColor), fillColor=\(fillColor)")

        if startX < 0 || startX>=width || startY < 0 || startY>=height {
            return
        }
        let curr = getPixelColor(pixels, width, height, startX, startY)
        if curr != targetColor { return }

        setPixelColor(&pixels, width, height, startX, startY, fillColor)
        seedFillRecursive(&pixels, width, height, startX+1, startY, targetColor, fillColor)
        seedFillRecursive(&pixels, width, height, startX - 1, startY, targetColor, fillColor)
        seedFillRecursive(&pixels, width, height, startX, startY+1, targetColor, fillColor)
        seedFillRecursive(&pixels, width, height, startX, startY - 1, targetColor, fillColor)

        print("[seedFillStack] done.")
    }

    // MARK: - 2) Seed fill (stack)

    public static func seedFillStack(
        _ pixels: inout [UInt8],
        _ width: Int,
        _ height: Int,
        _ startX: Int,
        _ startY: Int,
        _ targetColor: (UInt8, UInt8, UInt8, UInt8),
        _ fillColor: (UInt8, UInt8, UInt8, UInt8)
    ) {
        print("[seedFillStack] start from (\(startX), \(startY)), targetColor=\(targetColor), fillColor=\(fillColor)")

        var stack: [IntPoint] = []
        stack.append(IntPoint(startX, startY))

        var count = 0
        while !stack.isEmpty {
            let pt = stack.removeLast()
            let x = pt.x
            let y = pt.y
            if x < 0 || x>=width || y < 0 || y>=height {
                continue
            }
            let curr = getPixelColor(pixels, width, height, x, y)
            if curr == targetColor {
                setPixelColor(&pixels, width, height, x, y, fillColor)
                stack.append(IntPoint(x+1, y))
                stack.append(IntPoint(x - 1, y))
                stack.append(IntPoint(x, y+1))
                stack.append(IntPoint(x, y - 1))
            }

            count += 1
            if count % 10000 == 0 {
                print(" -> [seedFillStack] processed \(count) pixels so far…")
            }
        }
        print("[seedFillStack] done, processed \(count) pixels.")
    }

    // MARK: - 3) Scanline fill

    public static func scanlineFill(
        _ pixels: inout [UInt8],
        _ width: Int,
        _ height: Int,
        _ startX: Int,
        _ startY: Int,
        _ targetColor: (UInt8, UInt8, UInt8, UInt8),
        _ fillColor: (UInt8, UInt8, UInt8, UInt8)
    ) {
        print("[scanlineFill] start from (\(startX), \(startY)), targetColor=\(targetColor), fillColor=\(fillColor)")

        var stack: [IntPoint] = []
        stack.append(IntPoint(startX, startY))

        var count = 0
        while !stack.isEmpty {
            let pt = stack.removeLast()
            let y = pt.y
            var x = pt.x

            if y < 0 || y>=height { continue }

            // move left
            while x>=0, getPixelColor(pixels, width, height, x, y) == targetColor {
                x -= 1
            }
            let left = x+1

            // move right
            x = pt.x+1
            while x < width, getPixelColor(pixels, width, height, x, y) == targetColor {
                x += 1
            }
            let right = x - 1

            // fill line
            if left<=right {
                for fillX in left ... right {
                    setPixelColor(&pixels, width, height, fillX, y, fillColor)
                }

                // above
                let rowUp = y - 1
                if rowUp>=0 {
                    var checkX = left
                    while checkX<=right {
                        let c = getPixelColor(pixels, width, height, checkX, rowUp)
                        if c == targetColor {
                            stack.append(IntPoint(checkX, rowUp))
                            while checkX<=right, getPixelColor(pixels, width, height, checkX, rowUp) == targetColor {
                                checkX += 1
                            }
                        }
                        checkX += 1
                    }
                }

                // below
                let rowDown = y+1
                if rowDown < height {
                    var checkX = left
                    while checkX<=right {
                        let c = getPixelColor(pixels, width, height, checkX, rowDown)
                        if c == targetColor {
                            stack.append(IntPoint(checkX, rowDown))
                            while checkX<=right, getPixelColor(pixels, width, height, checkX, rowDown) == targetColor {
                                checkX += 1
                            }
                        }
                        checkX += 1
                    }
                }
            }

            count += 1
            if count % 10000 == 0 {
                print(" -> [scanlineFill] processed \(count) pixels so far…")
            }
        }
        print("[scanlineFill] done, processed \(count) pixels.")
    }

    // MARK: - 4) LCA fill

    public static func fillPolygonLCA(
        polygon: [SIMD2<Float>],
        pixels: inout [UInt8],
        width: Int,
        height: Int,
        fillColor: (UInt8, UInt8, UInt8, UInt8),
        fillRule: FillRule
    ) {
        print("[fillPolygonLCA] polygon has \(polygon.count) vertices")
        print("LCA Fill rule selected: \(fillRule)")
        let intPoints = polygon.map { IntPoint(Int($0.x.rounded()), Int($0.y.rounded())) }
        guard intPoints.count>=3 else { return }

        var minY = Int.max
        var maxY = Int.min
        for p in intPoints {
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        if minY < 0 { minY = 0 }
        if maxY>=height { maxY = height - 1 }

        // Build edges
        var edges: [LCAEdge] = []
        for i in 0..<intPoints.count {
            let j = (i+1) % intPoints.count
            var x1 = intPoints[i].x
            var y1 = intPoints[i].y
            var x2 = intPoints[j].x
            var y2 = intPoints[j].y
            if y1 == y2 { continue }
            if y2 < y1 {
                swap(&x1, &x2)
                swap(&y1, &y2)
            }
            let dy = Float(y2 - y1)
            let dx = Float(x2 - x1)
            let invSlope = dx / dy
            edges.append(LCAEdge(yMin: y1, yMax: y2, xOfYMin: Float(x1), invSlope: invSlope))
        }

        var active: [LCAEdge] = []

        for scanY in minY ... maxY {
            // Add edges that start at scanY
            for e in edges {
                if e.yMin == scanY {
                    active.append(e)
                }
            }
            // Remove edges that end at scanY
            active.removeAll { $0.yMax == scanY }

            // Update currentX
            for i in 0..<active.count {
                let old = active[i]
                let newX = old.xOfYMin+old.invSlope*Float(scanY - old.yMin)
                var updated = old
                updated.currentX = newX
                active[i] = updated
            }

            // Sort by currentX
            active.sort { $0.currentX < $1.currentX }

            switch fillRule {
            case .evenOdd:
                var i = 0
                while i < active.count - 1 {
                    let x1 = Int(active[i].currentX.rounded())
                    let x2 = Int(active[i+1].currentX.rounded())
                    fillLine(&pixels, width, height, scanY, x1, x2, fillColor)
                    i += 2
                }

            case .winding:
                // Simple approach: we traverse edges in order and increment windingCount if edge goes up,
                // decrement if edge goes down. Then we fill the segments where windingCount != 0.

                var wCount = 0
                var prevX = 0
                for i in 0..<active.count {
                    // Current edge
                    let e = active[i]
                    // Current X
                    let curX = Int(e.currentX.rounded())

                    // If wCount != 0, fill from prevX..curX
                    if wCount != 0 {
                        fillLine(&pixels, width, height, scanY, prevX, curX, fillColor)
                    }

                    // Update windingCount
                    // If the edge is ascending => yMin->yMax => +1
                    // If the edge is descending => -1
                    // (In LCA, we stored edges so yMin < yMax, so it's always ascending in this data structure.
                    //  If we had edges that can be reversed, we woul'd adapt the logic.)
                    wCount += 1

                    // Move prevX to curX
                    prevX = curX
                }

            case .both:
                // Combine both methods (logical OR):
                // If a pixel is in even-odd OR winding => fill it.
                // We'll track them separately, then fill if (evenOddIn || windingIn).
                // For efficiency, we might do a single pass with combined logic.

                // 1) Even-odd pass: gather intervals
                var intervalsEvenOdd: [(Int, Int)] = []
                do {
                    var i = 0
                    while i < active.count - 1 {
                        let x1 = Int(active[i].currentX.rounded())
                        let x2 = Int(active[i+1].currentX.rounded())
                        intervalsEvenOdd.append((min(x1, x2), max(x1, x2)))
                        i += 2
                    }
                }

                // 2) Winding pass
                var intervalsWinding: [(Int, Int)] = []
                do {
                    var wCount = 0
                    var prevX = 0
                    for i in 0..<active.count {
                        let e = active[i]
                        let curX = Int(e.currentX.rounded())

                        if wCount != 0 {
                            intervalsWinding.append((min(prevX, curX), max(prevX, curX)))
                        }
                        wCount += 1
                        prevX = curX
                    }
                }

                // 3) Merge intervals => fill

                let minX = (intervalsEvenOdd+intervalsWinding)
                    .map { $0.0 }.min() ?? Int(active.first?.currentX.rounded() ?? 0)
                let maxX = (intervalsEvenOdd+intervalsWinding)
                    .map { $0.1 }.max() ?? Int(active.last?.currentX.rounded() ?? 0)

                for xPixel in minX ... maxX {
                    let inEvenOdd = intervalsEvenOdd.contains(where: { xPixel>=$0.0 && xPixel < $0.1 })
                    let inWinding = intervalsWinding.contains(where: { xPixel>=$0.0 && xPixel < $0.1 })
                    if inEvenOdd || inWinding {
                        setPixelColor(&pixels, width, height, xPixel, scanY, fillColor)
                    }
                }
            }
        }
        print("[fillPolygonLCA] done.")
    }

    private static func fillLine(_ buf: inout [UInt8],
                                 _ w: Int, _ h: Int,
                                 _ y: Int,
                                 _ x1: Int, _ x2: Int,
                                 _ color: (UInt8, UInt8, UInt8, UInt8))
    {
        let start = min(x1, x2)
        let end = max(x1, x2)
        for x in start..<end {
            if x>=0, x < w, y>=0, y < h {
                setPixelColor(&buf, w, h, x, y, color)
            }
        }
    }

    // MARK: - Edge structure

    fileprivate struct LCAEdge {
        let yMin: Int
        let yMax: Int
        let xOfYMin: Float
        let invSlope: Float
        var currentX: Float = 0
    }

    // MARK: - Pixel helpers

    public static func getPixelColor(_ buf: [UInt8],
                                     _ w: Int,
                                     _ h: Int,
                                     _ x: Int,
                                     _ y: Int) -> (UInt8, UInt8, UInt8, UInt8)
    {
        let idx = (y*w+x)*4
        return (buf[idx], buf[idx+1], buf[idx+2], buf[idx+3])
    }

    public static func setPixelColor(_ buf: inout [UInt8],
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
