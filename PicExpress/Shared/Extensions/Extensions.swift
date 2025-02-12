//
//  Extensions.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import AppKit
import Foundation
import RealityKit
import SwiftUICore

extension Double {
    var degreesToRadians: Double { return self * .pi / 180 }
}

/// Helper extension to create float4x4 easily
extension float4x4 {
    init(rotationX angle: Float) {
        self = float4x4(
            [1, 0, 0, 0],
            [0, cos(angle), sin(angle), 0],
            [0, -sin(angle), cos(angle), 0],
            [0, 0, 0, 1]
        )
    }

    init(rotationY angle: Float) {
        self = float4x4(
            [cos(angle), 0, -sin(angle), 0],
            [0, 1, 0, 0],
            [sin(angle), 0, cos(angle), 0],
            [0, 0, 0, 1]
        )
    }

    init(rotationZ angle: Float) {
        self = float4x4(
            [cos(angle), sin(angle), 0, 0],
            [-sin(angle), cos(angle), 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        )
    }

    init(_ c0: simd_float4,
         _ c1: simd_float4,
         _ c2: simd_float4,
         _ c3: simd_float4)
    {
        self.init(columns: (c0, c1, c2, c3))
    }
}

public extension Sequence {
    /// Groups up elements of `self` into a new Dictionary,
    /// whose values are Arrays of grouped elements,
    /// each keyed by the group key returned by the given closure.
    /// - Parameters:
    ///   - keyForValue: A closure that returns a key for each element in
    ///     `self`.
    /// - Returns: A dictionary containing grouped elements of self, keyed by
    ///     the keys derived by the `keyForValue` closure.
    @inlinable
    func grouped<GroupKey>(by keyForValue: (Element) throws -> GroupKey) rethrows -> [GroupKey: [Element]] {
        try Dictionary(grouping: self, by: keyForValue)
    }
}

extension Color {
    /// Convert the SwiftUI color to a SIMD4<Float> in RGBA order
    func toSIMD4() -> SIMD4<Float> {
        let nsColor = NSColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        if let converted = nsColor.usingColorSpace(.deviceRGB) {
            converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        }

        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }
}

extension Color {
    /// Converts a SwiftUI Color to an MTLClearColor
    func toMTLClearColor() -> MTLClearColor {
        let nsColor = NSColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        if let converted = nsColor.usingColorSpace(.deviceRGB) {
            converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        }

        return MTLClearColorMake(Double(r), Double(g), Double(b), Double(a))
    }
}

extension simd_int4 {
    func contains(_ value: Int32) -> Bool {
        return x == value || y == value || z == value || w == value
    }
}
