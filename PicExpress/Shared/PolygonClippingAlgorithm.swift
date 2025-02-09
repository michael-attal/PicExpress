//
//  PolygonClippingAlgorithm.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

import Foundation
import simd

/// Enumeration of polygon clipping/triangulation algorithms
public enum PolygonClippingAlgorithm: String, Identifiable, CaseIterable, Sendable {
    public var id: String { rawValue }

    /// Triangulation via Ear Clipping
    case earClipping = "Ear Clipping"

    /// Cyrus-Beck parametric clipping
    case cyrusBeck = "Cyrus-Beck"

    /// Clipping polygonal Sutherland-Hodgman
    case sutherlandHodgman = "Sutherland-Hodgman"
}

public func sutherlandHodgmanClip(
    subjectPolygon: [ECTPoint],
    clipWindow: [ECTPoint]
) -> [ECTPoint] {
    guard subjectPolygon.count >= 3, clipWindow.count >= 3 else {
        return []
    }

    var outputList = subjectPolygon

    for i in 0 ..< clipWindow.count {
        let pA = clipWindow[i]
        let pB = clipWindow[(i + 1) % clipWindow.count]

        let inputList = outputList
        outputList = []
        if inputList.isEmpty {
            break
        }

        for j in 0 ..< inputList.count {
            let currentPoint = inputList[j]
            let nextPoint = inputList[(j + 1) % inputList.count]

            let currentInside = isInsideSH(point: currentPoint, clipA: pA, clipB: pB)
            let nextInside = isInsideSH(point: nextPoint, clipA: pA, clipB: pB)

            if currentInside, nextInside {
                outputList.append(nextPoint)
            } else if currentInside, !nextInside {
                if let inter = computeIntersectionSH(
                    cPoint: currentPoint,
                    nPoint: nextPoint,
                    clipA: pA,
                    clipB: pB
                ) {
                    outputList.append(inter)
                }
            } else if !currentInside, nextInside {
                if let inter = computeIntersectionSH(
                    cPoint: currentPoint,
                    nPoint: nextPoint,
                    clipA: pA,
                    clipB: pB
                ) {
                    outputList.append(inter)
                }
                outputList.append(nextPoint)
            }
        }
    }
    return outputList
}

private func isInsideSH(point: ECTPoint, clipA: ECTPoint, clipB: ECTPoint) -> Bool {
    let edge = clipB - clipA
    let toPoint = point - clipA
    // crossZ >= 0 => left
    let crossZ = edge.x*toPoint.y - edge.y*toPoint.x
    return crossZ >= 0
}

private func computeIntersectionSH(
    cPoint: ECTPoint,
    nPoint: ECTPoint,
    clipA: ECTPoint,
    clipB: ECTPoint
) -> ECTPoint? {
    let dS = nPoint - cPoint
    let dW = clipB - clipA

    let denom = dS.x*dW.y - dS.y*dW.x
    if abs(denom) < 1e-12 {
        return nil
    }

    let x1 = cPoint.x, y1 = cPoint.y
    let x2 = nPoint.x, y2 = nPoint.y
    let x3 = clipA.x, y3 = clipA.y
    let x4 = clipB.x, y4 = clipB.y

    let numPX = ((x1*y2 - y1*x2)*(x3 - x4)) - ((x1 - x2)*(x3*y4 - y3*x4))
    let numPY = ((x1*y2 - y1*x2)*(y3 - y4)) - ((y1 - y2)*(x3*y4 - y3*x4))

    let px = numPX / denom
    let py = numPY / denom

    return ECTPoint(x: px, y: py)
}

public func cyrusBeckClip(
    subjectPolygon: [ECTPoint],
    clipWindow: [ECTPoint]
) -> [ECTPoint] {
    guard subjectPolygon.count >= 3, clipWindow.count >= 3 else {
        return []
    }

    var outputList = subjectPolygon

    for i in 0 ..< clipWindow.count {
        let A = clipWindow[i]
        let B = clipWindow[(i + 1) % clipWindow.count]

        let inputList = outputList
        outputList = []
        if inputList.isEmpty { break }

        for j in 0 ..< inputList.count {
            let currentPoint = inputList[j]
            let nextPoint = inputList[(j + 1) % inputList.count]

            if let seg = cyrusBeckSegmentClip(
                p1: currentPoint,
                p2: nextPoint,
                clipA: A,
                clipB: B,
                isCCWwindow: true
            ) {
                let (clipP1, clipP2) = seg
                let inside1 = isInsideCB(clipP1, A, B)
                let inside2 = isInsideCB(clipP2, A, B)

                if inside1, inside2 {
                    outputList.append(clipP2)
                } else if inside1, !inside2 {
                    // in->out => pas de p2
                } else if !inside1, inside2 {
                    // out->in => ajoute clipP1 + clipP2
                    outputList.append(clipP1)
                    outputList.append(clipP2)
                }
            }
        }
    }

    return outputList
}

private func cyrusBeckSegmentClip(
    p1: ECTPoint,
    p2: ECTPoint,
    clipA: ECTPoint,
    clipB: ECTPoint,
    isCCWwindow: Bool
) -> (ECTPoint, ECTPoint)? {
    let d = p2 - p1
    if abs(d.x) < 1e-12 && abs(d.y) < 1e-12 {
        if isInsideCB(p1, clipA, clipB) {
            return (p1, p1)
        } else {
            return nil
        }
    }

    var tinf = 0.0
    var tsup = 1.0

    let edge = clipB - clipA
    let nx = -edge.y
    let ny = edge.x

    let denom = d.x*nx + d.y*ny
    let num = (clipA.x - p1.x)*nx + (clipA.y - p1.y)*ny

    if abs(denom) < 1e-12 {
        // segment // bord
        if num < 0 {
            return nil
        } else {
            return (p1, p2)
        }
    }

    let tIntersect = num / denom

    if denom > 0 {
        if tIntersect > tinf {
            tinf = tIntersect
        }
    } else {
        if tIntersect < tsup {
            tsup = tIntersect
        }
    }

    if tinf > tsup {
        return nil
    }
    if tsup < 0 || tinf > 1 {
        return nil
    }

    let finalTinf = max(0.0, min(1.0, tinf))
    let finalTsup = max(0.0, min(1.0, tsup))
    if finalTinf > finalTsup {
        return nil
    }

    let start = ECTPoint(
        x: p1.x + d.x*finalTinf,
        y: p1.y + d.y*finalTinf
    )
    let end = ECTPoint(
        x: p1.x + d.x*finalTsup,
        y: p1.y + d.y*finalTsup
    )

    return (start, end)
}

private func isInsideCB(_ pt: ECTPoint, _ A: ECTPoint, _ B: ECTPoint) -> Bool {
    let e = B - A
    let n = ECTPoint(x: -e.y, y: e.x)
    let v = pt - A
    let dotp = n.x*v.x + n.y*v.y
    return dotp >= 0
}
