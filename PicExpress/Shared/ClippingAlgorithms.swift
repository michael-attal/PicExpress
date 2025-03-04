//
//  ClippingAlgorithms.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

import Foundation
import RealityKit

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

    /// Clips a segment (start, end) with a clipWindow convex polygon.
    /// Returns true/false depending on whether the resulting segment is non-empty or not.
    /// If true, we modify in-place segment.start and segment.end so that they are truncated at the borders.
    ///
    /// Warning: 'clipWindow' must be in order (e.g. CCW) and closed (last side = [last, 0]).
    public static func cyrusBeckClip(
        segment: inout (start: SIMD2<Float>, end: SIMD2<Float>),
        clipWindow: [SIMD2<Float>]
    ) -> Bool
    {
        let n = clipWindow.count
        // Security
        guard n>=3 else { return false }

        // Parameters tinf / tsup
        var tInf: Float = -Float.infinity
        var tSup = Float.infinity

        // The segment direction vector
        let D = segment.end - segment.start

        // Traverse all edges
        for i in 0..<n
        {
            // Current edge
            let j = (i + 1)%n
            let Pi = clipWindow[i]
            let Pi1 = clipWindow[j]

            let edge = Pi1 - Pi
            let normal = SIMD2<Float>(-edge.y, edge.x) // If the window is CCW: default is normal = ( -dy, +dx )

            let denom = simd_dot(D, normal) // DN
            let W = segment.start - Pi
            let numer = simd_dot(W, normal) // WN

            if abs(denom) < 1e-7
            {
                // => Segment parallel to this edge
                if numer < 0
                {
                    // => Complet outside window => we can exit directly
                    return false
                }
                else
                {
                    // => The segment is parallel but “on the right side” => continue
                    continue
                }
            }
            else
            {
                // => Calculate t
                let t = -numer / denom

                // denom > 0 => “low neighbor” => update tInf
                // denom < 0 => “high neighbor” => update tSup
                if denom > 0
                {
                    if t > tInf
                    {
                        tInf = t
                    }
                }
                else
                {
                    if t < tSup
                    {
                        tSup = t
                    }
                }
            }
        }

        // At the end, if tInf <= tSup, we may have a segment
        if tInf > tSup
        {
            // No intersection
            return false
        }

        // Intervals of 0..1 => can still be cut
        if tInf > 1 || tSup < 0
        {
            // Segment completely outside
            return false
        }

        // clamp tInf/tSup in [0..1]
        let t0 = max(tInf, 0)
        let t1 = min(tSup, 1)
        if t0 > t1
        {
            return false
        }

        // Segment update
        // start
        let newStart = segment.start + D*t0
        let newEnd = segment.start + D*t1
        segment.start = newStart
        segment.end = newEnd

        return true
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
        if abs(denom) < 1e-12 { return nil }
        let num = -(W.x*nx + W.y*ny)
        let t = num / denom
        if t < 0 || t > 1 { return nil }
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
        if abs(denom) < 1e-12 { return nil }
        let num = W.x*(-AB.y) + W.y*(AB.x)
        let t = -num / denom
        if t < 0 || t > 1 { return nil }
        return c + t*D
    }
}

private extension ClippingAlgorithms
{
    private static func dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float
    {
        return a.x*b.x + a.y*b.y
    }
}
