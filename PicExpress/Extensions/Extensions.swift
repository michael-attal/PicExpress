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
}
