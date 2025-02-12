//
//  TriangulationAlgorithms.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import AppKit
import CoreGraphics
import Foundation
import simd
import SwiftUICore

// NOTE: MARK: - Data Structures

enum AvailableTriangulationAlgorithm: String, Identifiable, CaseIterable, Sendable, SelectionItem {
    public var id: String { rawValue }
    case earClipping = "Ear Clipping"

    public var description: String { rawValue }
}

// MARK: - Ear Clipping Triangulation

public typealias ECTPoint = SIMD2<Double>

struct ECTEdge {
    var start: ECTPoint
    var end: ECTPoint
}

public struct ECTPolygon {
    let vertices: [ECTPoint]
    let verticeFirstIndices: [ECTPoint: Int]

    public init(vertices: [ECTPoint]) {
        self.vertices = vertices
        self.verticeFirstIndices = vertices.enumerated().grouped { entry in
            entry.element
        }.compactMapValues { $0.first?.offset }
    }
}

struct ECTTriangle {
    var a: ECTPoint
    var b: ECTPoint
    var c: ECTPoint
}

struct ECTPolygonTree {
    var p: ECTPolygon
    var children: [ECTPolygonTree]
}

// MARK: - EarClippingTriangulation Class. Inspired from https://www.geometrictools.com/Documentation/TriangulationByEarClipping.pdf

class EarClippingTriangulation {
    var triangles: [ECTTriangle] = []
    let epsilon = 1e-9 // NOTE: Tolerance for floating-point comparisons
    
    func triangulate(polygonTree: ECTPolygonTree) -> [ECTTriangle] {
        triangles = []
        var queue: [ECTPolygonTree] = []
        queue.append(polygonTree)
        
        while !queue.isEmpty {
            let outerNode = queue.removeFirst()
            let numChildren = outerNode.children.count
            
            if numChildren == 0 {
                // NOTE: The outer polygon is a simple polygon without nested polygons.
                triangles += getEarClipTriangles(polygon: outerNode.p)
            } else {
                // NOTE: The outer polygon contains inner polygons.
                var innerPolygons: [ECTPolygon] = []
                
                for innerNode in outerNode.children {
                    innerPolygons.append(innerNode.p)
                    
                    if !innerNode.children.isEmpty {
                        for grandchild in innerNode.children {
                            queue.insert(grandchild, at: 0)
                        }
                    }
                }
                
                let combined = combineToPseudoSimple(outer: outerNode.p, inners: innerPolygons)
                
                triangles += getEarClipTriangles(polygon: combined)
            }
        }
        
        return triangles
    }
    
    // MARK: - Ear Clipping Triangulation
    
    func getEarClipTriangles(polygon: ECTPolygon) -> [ECTTriangle] {
        var triangles: [ECTTriangle] = []
        var vertices = polygon.vertices
        
        // NOTE: Ensure the polygon is counterclockwise; if not, reverse the vertices
        if !isCounterClockwise(polygon: polygon) {
            vertices.reverse()
        }
        
        var nv = vertices.count
        if nv < 3 {
            return []
        }
        
        // NOTE: Initialize vertex indices
        var V = [Int](0..<nv)
        
        var count = 0
        while nv > 3 {
            var earFound = false
            
            for i in 0..<nv {
                let prev = V[(i + nv - 1) % nv]
                let curr = V[i]
                let next = V[(i + 1) % nv]
                
                let a = vertices[prev]
                let b = vertices[curr]
                let c = vertices[next]
                
                if isConvex(a: a, b: b, c: c) {
                    var isEar = true
                    
                    for j in 0..<nv {
                        let vi = V[j]
                        if vertices[vi] == a || vertices[vi] == b || vertices[vi] == c {
                            continue
                        }
                        
                        if pointInTriangle(p: vertices[vi], a: a, b: b, c: c) {
                            isEar = false
                            break
                        }
                    }
                    
                    if isEar {
                        triangles.append(ECTTriangle(a: a, b: b, c: c))
                        V.remove(at: i)
                        nv -= 1
                        earFound = true
                        break
                    }
                }
            }
            
            if !earFound {
                break
            }
            
            count += 1
            if count > 1000 {
                print("Boucle infinie détectée.")
                break
            }
        }
        
        if nv == 3 {
            let a = vertices[V[0]]
            let b = vertices[V[1]]
            let c = vertices[V[2]]
            triangles.append(ECTTriangle(a: a, b: b, c: c))
        }
        
        return triangles
    }
    
    // NOTE: Auxiliary functions for Ear Clipping
    
    func isCounterClockwise(polygon: ECTPolygon) -> Bool {
        return signedArea(polygon: polygon) > 0
    }
    
    func signedArea(polygon: ECTPolygon) -> Double {
        let vertices = polygon.vertices
        var area = 0.0
        let n = vertices.count
        for i in 0..<n {
            let vi = vertices[i]
            let vj = vertices[(i + 1) % n]
            area += simd_determinant(simd_double2x2(vi, vj))
        }
        return area / 2.0
    }
    
    @inline(__always) func isConvex(a: ECTPoint, b: ECTPoint, c: ECTPoint) -> Bool {
        return simd_determinant(simd_double2x2(b - a, c - b)) > epsilon
    }
    
    @inline(__always) func pointInTriangle(p: ECTPoint, a: ECTPoint, b: ECTPoint, c: ECTPoint) -> Bool {
        // NOTE: Compute vectors
        let v0 = c - a
        let v1 = b - a
        let v2 = p - a
        
        // NOTE: Compute dot products
        let dot00 = simd_dot(v0, v0)
        let dot01 = simd_dot(v0, v1)
        let dot02 = simd_dot(v0, v2)
        let dot11 = simd_dot(v1, v1)
        let dot12 = simd_dot(v1, v2)
        
        // NOTE: Compute barycentric coordinates
        let denom = simd_determinant(simd_double2x2([dot00, dot01], [dot01, dot11])) // dot00 * dot11 - dot01 * dot01
        if abs(denom) < epsilon {
            return false // NOTE: The triangle is degenerate
        }
        
        let uv: SIMD2<Double> = (SIMD2(dot11 * dot02, dot00 * dot12) - SIMD2(dot01 * dot12, dot01 * dot02)) / denom
        // NOTE: Check if point is in triangle
        return (uv.x >= -epsilon) && (uv.y >= -epsilon) && (uv.x + uv.y <= 1.0 + epsilon)
    }
    
    // MARK: - Combining into a Pseudo-Simple Polygon
    
    func combineToPseudoSimple(outer: ECTPolygon, inners: [ECTPolygon]) -> ECTPolygon {
        // var combinedPolygon = outer
        var result: [ECTPoint] = outer.vertices
        var holes = inners
        
        while !holes.isEmpty {
            // NOTE: Step 1: Find the hole with the vertex of maximum x-coordinate
            let holeIndex = holes.indices.max(by: { maxX(of: holes[$0]) < maxX(of: holes[$1]) })!
            let hole = holes.remove(at: holeIndex)
            
            // NOTE: Step 2: Find the vertex M with the maximum x-coordinate in the hole
            let innerMaxXVertexIndex = hole.vertices.indices.max(by: { hole.vertices[$0].x < hole.vertices[$1].x })!
            let M = hole.vertices[innerMaxXVertexIndex]
            
            // NOTE: Step 3: Find the closest visible vertex from M on the outer polygon
            let (visibleVertexIndex, _) = findVisibleVertex(from: M, in: result)
            
            // NOTE: Step 4: Introduce a bridge between M and P
            if let index = visibleVertexIndex {
                // NOTE: Rearrange hole vertices to start after M
                let holeVertices = rearrangedHoleVertices(hole: hole, startingAt: (innerMaxXVertexIndex + 1) % hole.vertices.count)
                
                // NOTE: Build the new vertices of the combined polygon
                var newVertices = [ECTPoint]()
                let insertionIndex = index + 1
                
                // NOTE: Part of the outer polygon before point P (inclusive)
                newVertices += result[0 ... index]
                // NOTE: Add M (start of the bridge)
                newVertices.append(M)
                // NOTE: Add hole vertices (excluding M)
                newVertices += holeVertices
                // NOTE: Add the remaining outer polygon vertices after P
                if insertionIndex < result.count {
                    newVertices += result[insertionIndex..<result.count]
                }
                // combinedPolygon.vertices = newVertices
                result = newVertices
            } else {
                // NOTE: No visible vertex found; this should not happen if polygons are properly nested
                print("Aucun sommet visible trouvé entre M et le polygone extérieur.")
            }
        }
        
        return ECTPolygon(vertices: result)
    }
    
    // NOTE: Auxiliary functions for combining
    
    func maxX(of polygon: ECTPolygon) -> Double {
        return polygon.vertices.map(\.x).max() ?? Double.leastNormalMagnitude
    }
    
    func findVisibleVertex(from M: ECTPoint, in vertices: [ECTPoint]) -> (Int?, ECTPoint) {
        let rayDirection = ECTPoint(x: 1, y: 0)
        var minT = Double.greatestFiniteMagnitude
        var visibleVertexIndex: Int?
        var P = ECTPoint(x: 0, y: 0)
        
        let n = vertices.count
        for i in 0..<n {
            let A = vertices[i]
            let B = vertices[(i + 1) % n]
            
            // NOTE: Check if M is strictly to the left of the edge (A -> B)
            let cp = simd_determinant(simd_double2x2(B - A, M - B))
            if cp <= epsilon {
                continue
            }
            
            // NOTE: Check if the segment crosses the horizontal line y = M.y
            if (A.y > M.y && B.y > M.y) || (A.y < M.y && B.y < M.y) {
                continue
            }
            
            // NOTE: Check if the ray from M intersects the edge (A, B)
            if let t = computeIntersectionParameter(M: M, rayDir: rayDirection, edge: (A, B)) {
                if t < minT {
                    minT = t
                    // NOTE: Take the vertex with the maximum x-coordinate
                    if A.x > B.x {
                        P = A
                        visibleVertexIndex = i
                    } else {
                        P = B
                        visibleVertexIndex = (i + 1) % n
                    }
                }
            }
        }
        
        return (visibleVertexIndex, P)
    }
    
    @inline(__always) func computeIntersectionParameter(M: ECTPoint, rayDir: ECTPoint, edge: (ECTPoint, ECTPoint)) -> Double? {
        let A = edge.0
        let B = edge.1
        
        let edgeDir = B - A
        let delta = A - M
        
        let denominator = simd_determinant(simd_double2x2(rayDir, edgeDir))
        
        if abs(denominator) < epsilon {
            return nil // NOTE: Segments are parallel
        }
        
        let tu_num = SIMD2(-simd_determinant(simd_double2x2(delta, edgeDir)), simd_determinant(simd_double2x2(rayDir, edgeDir)))
        let tu = tu_num / denominator
        
        // NOTE: Check if intersection is valid
        if tu.x >= -epsilon, tu.y >= -epsilon, tu.y <= 1.0 + epsilon {
            return tu.x // NOTE: Return t, the parameter along the ray
        } else {
            return nil
        }
    }
    
    func rearrangedHoleVertices(hole: ECTPolygon, startingAt index: Int) -> [ECTPoint] {
        var vertices = hole.vertices
        let n = vertices.count
        // NOTE: Rearrange vertices to start at M
        if index != 0 {
            vertices = Array(vertices[index..<n] + vertices[0..<index])
        }
        // NOTE: Reverse vertices if they are not clockwise
        if !isClockwise(polygon: ECTPolygon(vertices: vertices)) {
            vertices.reverse()
        }
        return vertices
    }
    
    func isClockwise(polygon: ECTPolygon) -> Bool {
        return signedArea(polygon: polygon) < 0
    }
    
    static func earClipOnePolygon(
        ectPoints: [ECTPoint],
        color: Color,
        existingVertexCount: Int
    ) -> ([PolygonVertex], [UInt16]) {
        let ectPoly = ECTPolygon(vertices: ectPoints)
        
        let earClip = EarClippingTriangulation()
        let triangles = earClip.getEarClipTriangles(polygon: ectPoly)
        
        let col = color.toSIMD4()
        
        // Construction of Vertex Indices
        var newVerts: [PolygonVertex] = []
        var newInds: [UInt16] = []
        var currentIndex = UInt16(existingVertexCount)
        
        for tri in triangles {
            let A = SIMD2<Float>(Float(tri.a.x), Float(tri.a.y))
            let B = SIMD2<Float>(Float(tri.b.x), Float(tri.b.y))
            let C = SIMD2<Float>(Float(tri.c.x), Float(tri.c.y))
            
            let iA = currentIndex
            let iB = currentIndex + 1
            let iC = currentIndex + 2
            currentIndex += 3
            
            newInds.append(iA)
            newInds.append(iB)
            newInds.append(iC)
            
            newVerts.append(PolygonVertex(position: A,
                                          uv: .zero,
                                          color: col))
            newVerts.append(PolygonVertex(position: B,
                                          uv: .zero,
                                          color: col))
            newVerts.append(PolygonVertex(position: C,
                                          uv: .zero,
                                          color: col))
        }
        
        return (newVerts, newInds)
    }
}
