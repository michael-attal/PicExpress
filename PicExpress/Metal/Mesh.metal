//
//  Mesh.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

#include <metal_stdlib>
using namespace metal;

/// This struct is passed from Swift and contains transform and doc size
struct TransformUniforms {
    float4x4 transform;     // 64 bytes
    float4   polygonColor;  // 16 => total 80
    float    docWidth;      // 4  => 84
    float    docHeight;     // 4  => 88
    float2   _padding;      // 8  => total 96
};

struct MeshVertex {
    float2 position;  // pixel coords
    float2 uv;
    float4 color;
    int4   polygonIDs; // up to 4 polygon IDs that share the same vertice
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

// Vertex shader: converts from pixel coords [0..width] to clip space [-1..1],
// then applies transform (zoom/pan).
vertex VertexOut vs_mesh(
    const device MeshVertex* vertices [[buffer(0)]],
    uint vid [[vertex_id]],
    constant TransformUniforms& uniforms [[buffer(1)]]
) {
    VertexOut out;

    float2 pixPos = vertices[vid].position;

    // 1) Convert pixel -> [-1..1]
    float2 ndc;
    ndc.x = (pixPos.x / uniforms.docWidth)  * 2.0 - 1.0;
    ndc.y = (pixPos.y / uniforms.docHeight) * 2.0 - 1.0;

    float4 worldPos = float4(ndc, 0.0, 1.0);

    // 2) Apply transform (zoom/pan)
    out.position = uniforms.transform * worldPos;

    // 3) uv = ratio pixel => [0..1]
    out.uv.x = pixPos.x / uniforms.docWidth;
    out.uv.y = pixPos.y / uniforms.docHeight;

    // Optional: we keep the color if we want to make a mix later
    out.color = vertices[vid].color;

    return out;
}

// Fragment shader: returns the color stored in the vertex
fragment float4 fs_mesh(VertexOut in [[stage_in]]) {
    return in.color;
}

/// New fragment shader to sample from a polygon's texture
fragment float4 fs_mesh_textured(
    VertexOut in [[stage_in]],
    texture2d<float> fillTex [[texture(0)]]
)
{
    constexpr sampler s(address::clamp_to_edge, filter::nearest);
    // On lit la couleur CPU dans fillTex, via in.uv
    float4 texColor = fillTex.sample(s, in.uv);
    return texColor;
    // Si on veut la multiplier par la color d'origine: `return texColor * in.color;`
}
