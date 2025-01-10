//
//  Polygon.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

#include <metal_stdlib>
using namespace metal;

struct TransformUniforms {
    float4x4 transform;
};

struct PolygonVertex {
    float2 position;
    float2 uv;
    float4 color; // each vertex contains its own color
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

// Vertex shader
vertex VertexOut vs_polygon(
    const device PolygonVertex* vertices [[buffer(0)]],
    uint vid [[vertex_id]],
    constant TransformUniforms& uniforms [[buffer(1)]]
) {
    VertexOut out;
    float2 pos = vertices[vid].position;
    float4 worldPos = float4(pos, 0.0, 1.0);

    out.position = uniforms.transform * worldPos; // Apply the transformation (zoom + pan)
    out.uv       = vertices[vid].uv;
    out.color    = vertices[vid].color;
    return out;
}

// Fragment shader
fragment float4 fs_polygon(VertexOut in [[stage_in]])
{
    // Returns the color stored in the vertex
    return in.color;
}
