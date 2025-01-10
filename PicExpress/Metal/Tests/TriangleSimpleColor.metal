//
//  TriangleSimpleColor.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//


#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vs_triangle_simple(uint vertexID [[vertex_id]]) {
    VertexOut out;
    
    // Array of the positions of our 3 vertices (a triangle).
    float2 positions[3] = {
        float2( 0.0,  0.5),
        float2(-0.5, -0.5),
        float2( 0.5, -0.5)
    };
    
    out.position = float4(positions[vertexID], 0.0, 1.0);
    // We draw the triangle in blue
    out.color = float4(0.0, 0.0, 1.0, 1.0);
    return out;
}

fragment float4 fs_triangle_simple(VertexOut in [[stage_in]]) {
    return in.color;
}