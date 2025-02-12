//
//  PointsPreview.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 08/02/2025.
//

#include <metal_stdlib>
using namespace metal;

/// The input vertex for a point (in pixel coords).
struct PointPreviewVertexIn {
    float2 position [[attribute(0)]];
};

/// Matches the Swift uniform struct, including docWidth/docHeight, and now zoomFactor.
struct PointsPreviewTransformUniforms {
    float4x4 transform;     // 64 bytes
    float4   polygonColor;  // 16 => total 80
    float    docWidth;      // 4  => 84
    float    docHeight;     // 4  => 88
    float    zoomFactor;    // 4  => 92
    float    _padding;      // 4  => total 96 (or adapt as needed)
};

struct PointsPreviewVSOut {
    float4 position [[position]];
    float4 color;
    float  pointSize [[point_size]];
};

// Vertex shader: convert from [0..docWidth] -> [-1..1], then apply transform.
vertex PointsPreviewVSOut vs_points_preview(
    PointPreviewVertexIn inVertex [[stage_in]],
    constant PointsPreviewTransformUniforms &uniforms [[buffer(1)]]
)
{
    PointsPreviewVSOut out;

    float2 pixPos = inVertex.position;

    // Convert pixel -> [-1..1]
    float2 ndc;
    ndc.x = (pixPos.x / uniforms.docWidth)  * 2.0 - 1.0;
    ndc.y = (pixPos.y / uniforms.docHeight) * 2.0 - 1.0;

    float4 pos = float4(ndc, 0.0, 1.0);

    // Then apply transform (zoom, pan)
    pos = uniforms.transform * pos;

    out.position = pos;
    out.color    = uniforms.polygonColor;

    // Make the point size depend on the zoomFactor:
    // For example, if we want the point to be 8.0 px at zoom=1,
    // we can do:
    out.pointSize = 8.0 * uniforms.zoomFactor;

    return out;
}

// Simple fragment shader that outputs the color
fragment float4 fs_points_preview(PointsPreviewVSOut inFrag [[stage_in]])
{
    return inFrag.color;
}
