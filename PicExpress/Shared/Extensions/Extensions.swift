//
//  Extensions.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import Foundation
import RealityKit

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

extension Sequence {
  /// Groups up elements of `self` into a new Dictionary,
  /// whose values are Arrays of grouped elements,
  /// each keyed by the group key returned by the given closure.
  /// - Parameters:
  ///   - keyForValue: A closure that returns a key for each element in
  ///     `self`.
  /// - Returns: A dictionary containing grouped elements of self, keyed by
  ///     the keys derived by the `keyForValue` closure.
  @inlinable
  public func grouped<GroupKey>(by keyForValue: (Element) throws -> GroupKey) rethrows -> [GroupKey: [Element]] {
    try Dictionary(grouping: self, by: keyForValue)
  }
}
