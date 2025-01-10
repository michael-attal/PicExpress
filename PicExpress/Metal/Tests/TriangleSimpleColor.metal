//
//  TriangleSimpleColor.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

#include <metal_stdlib>
using namespace metal;

struct TransformUniforms {
    float4x4 transform;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vs_triangle_simple(
    uint vertexID [[vertex_id]],
    constant TransformUniforms &uniforms [[buffer(1)]]
) {    VertexOut out;
    
    // Array of the positions of our 3 vertices (a triangle).
    float2 positions[3] = {
        float2( 0.0,  0.5),
        float2(-0.5, -0.5),
        float2( 0.5, -0.5)
    };
    
    float4 pos = float4(positions[vertexID], 0.0, 1.0);

    // Apply the transformation (zoom + pan)
    out.position = uniforms.transform * pos;
    
    // We draw the triangle in blue
    out.color = float4(0.0, 0.0, 1.0, 1.0);
    return out;
}

fragment float4 fs_triangle_simple(VertexOut in [[stage_in]]) {
    return in.color;
}
