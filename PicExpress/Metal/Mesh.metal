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

/// Each polygon vertex (in pixel coords)
struct MeshVertex {
    float2 position;  // pixel coords in [0..docWidth], [0..docHeight]
    float2 uv;
    float4 color;     // each vertex color
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
    
    // Fetch the pixel coords
    float2 pixPos = vertices[vid].position;

    // Convert pixel -> [-1..1]
    float2 ndc;
    ndc.x = (pixPos.x / uniforms.docWidth)  * 2.0 - 1.0;
    ndc.y = (pixPos.y / uniforms.docHeight) * 2.0 - 1.0;
    
    float4 worldPos = float4(ndc, 0.0, 1.0);
    // Apply the transform (zoom/pan)
    out.position = uniforms.transform * worldPos;

    out.uv    = vertices[vid].uv;
    out.color = vertices[vid].color;
    return out;
}

// Fragment shader: returns the color stored in the vertex (classic approach)
fragment float4 fs_mesh(VertexOut in [[stage_in]]) {
    return in.color;
}

/// New fragment shader to sample from a polygon's texture
/// We'll pass the texture as 'polyTex' in Swift (via setFragmentTexture).
/// We'll use in.uv to sample it.
fragment float4 fs_mesh_textured(VertexOut in [[stage_in]],
                                    texture2d<float> polyTex [[texture(0)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::nearest);
    float4 texColor = polyTex.sample(s, in.uv);
    return texColor;
}
