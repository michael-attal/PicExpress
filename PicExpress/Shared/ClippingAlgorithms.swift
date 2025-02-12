//
//  ClippingAlgorithms.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

import Foundation

/// Enumeration of polygon clipping/triangulation algorithms
public enum AvailableClippingAlgorithm: String, Identifiable, CaseIterable, Sendable, SelectionItem
{
    public var id: String { rawValue }

    /// Cyrus-Beck parametric clipping
    case cyrusBeck = "Cyrus-Beck"

    /// Clipping polygonal Sutherland-Hodgman
    case sutherlandHodgman = "Sutherland-Hodgman"

    /// Returns the rawValue as the description
    public var description: String { rawValue }
}

public enum ClippingAlgorithms
{
    // MARK: - Cyrus-Beck

    public static func cyrusBeckClip(subjectPolygon: [SIMD2<Float>],
                                     clipWindow: [SIMD2<Float>]) -> [SIMD2<Float>]
    {
        guard subjectPolygon.count>=3, clipWindow.count>=3 else { return [] }
        var output = subjectPolygon
        let n = clipWindow.count
        for i in 0..<n
        {
            let A = clipWindow[i]
            let B = clipWindow[(i + 1)%n]
            output = cyrusBeckEdgeClip(output, A, B)
            if output.isEmpty { break }
        }
        return output
    }

    private static func cyrusBeckEdgeClip(_ poly: [SIMD2<Float>],
                                          _ A: SIMD2<Float>,
                                          _ B: SIMD2<Float>) -> [SIMD2<Float>]
    {
        guard poly.count>=2 else { return [] }
        var newPoly: [SIMD2<Float>] = []
        for i in 0..<poly.count
        {
            let curr = poly[i]
            let next = poly[(i + 1)%poly.count]
            let currInside = isInsideCB(curr, A, B)
            let nextInside = isInsideCB(next, A, B)
            if currInside, nextInside
            {
                newPoly.append(next)
            }
            else if currInside, !nextInside
            {
                if let inter = cyrusBeckIntersect(curr, next, A, B)
                {
                    newPoly.append(inter)
                }
            }
            else if !currInside, nextInside
            {
                if let inter = cyrusBeckIntersect(curr, next, A, B)
                {
                    newPoly.append(inter)
                }
                newPoly.append(next)
            }
        }
        return newPoly
    }

    private static func isInsideCB(_ p: SIMD2<Float>,
                                   _ A: SIMD2<Float>,
                                   _ B: SIMD2<Float>) -> Bool
    {
        // We assume the clipWindow is in CCW order
        let AB = B - A
        let AP = p - A
        let nx = -AB.y
        let ny = AB.x
        let dot = nx*AP.x + ny*AP.y
        return dot>=0
    }

    private static func cyrusBeckIntersect(_ p1: SIMD2<Float>,
                                           _ p2: SIMD2<Float>,
                                           _ A: SIMD2<Float>,
                                           _ B: SIMD2<Float>) -> SIMD2<Float>?
    {
        let D = p2 - p1
        let W = p1 - A
        let AB = B - A
        let nx = -AB.y
        let ny = AB.x
        let denom = D.x*nx + D.y*ny
        if abs(denom)<1e-12 { return nil }
        let num = -(W.x*nx + W.y*ny)
        let t = num/denom
        if t<0 || t > 1 { return nil }
        return p1 + t*D
    }

    // MARK: - Sutherland-Hodgman

    public static func sutherlandHodgmanClip(subjectPolygon: [SIMD2<Float>],
                                             clipWindow: [SIMD2<Float>]) -> [SIMD2<Float>]
    {
        guard subjectPolygon.count>=3, clipWindow.count>=3 else { return [] }
        var output = subjectPolygon
        let n = clipWindow.count
        for i in 0..<n
        {
            let A = clipWindow[i]
            let B = clipWindow[(i + 1)%n]
            output = clipEdgeSH(output, A, B)
            if output.isEmpty { break }
        }
        return output
    }

    private static func clipEdgeSH(_ poly: [SIMD2<Float>],
                                   _ A: SIMD2<Float>,
                                   _ B: SIMD2<Float>) -> [SIMD2<Float>]
    {
        var newPoly: [SIMD2<Float>] = []
        for i in 0..<poly.count
        {
            let curr = poly[i]
            let next = poly[(i + 1)%poly.count]
            let currInside = isInsideSH(curr, A, B)
            let nextInside = isInsideSH(next, A, B)

            if currInside, nextInside
            {
                newPoly.append(next)
            }
            else if currInside, !nextInside
            {
                if let inter = intersectSH(curr, next, A, B)
                {
                    newPoly.append(inter)
                }
            }
            else if !currInside, nextInside
            {
                if let inter = intersectSH(curr, next, A, B)
                {
                    newPoly.append(inter)
                }
                newPoly.append(next)
            }
        }
        return newPoly
    }

    private static func isInsideSH(_ p: SIMD2<Float>,
                                   _ A: SIMD2<Float>,
                                   _ B: SIMD2<Float>) -> Bool
    {
        let AB = B - A
        let AP = p - A
        let crossZ = AB.x*AP.y - AB.y*AP.x
        return crossZ>=0
    }

    private static func intersectSH(_ c: SIMD2<Float>,
                                    _ n: SIMD2<Float>,
                                    _ A: SIMD2<Float>,
                                    _ B: SIMD2<Float>) -> SIMD2<Float>?
    {
        let D = n - c
        let W = c - A
        let AB = B - A
        let denom = D.x*(-AB.y) + D.y*(AB.x)
        if abs(denom)<1e-12 { return nil }
        let num = W.x*(-AB.y) + W.y*(AB.x)
        let t = -num/denom
        if t<0 || t > 1 { return nil }
        return c + t*D
    }
}
