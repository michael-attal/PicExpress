//
//  MetalRotationVertexStructureForTriangleTest.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit

struct MetalRotationVertexStructureForTriangleTest {
    let position3D: SIMD3<Float>
    let colorRGB: SIMD3<Float>
    
    static func buildDefaultVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = MemoryLayout<MetalRotationVertexStructureForTriangleTest>.offset(of: \.position3D)!
        
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = MemoryLayout<MetalRotationVertexStructureForTriangleTest>.offset(of: \.colorRGB)!
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<MetalRotationVertexStructureForTriangleTest>.stride
        
        return vertexDescriptor
    }
}
