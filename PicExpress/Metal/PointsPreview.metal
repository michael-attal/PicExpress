//
//  PointsPreview.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 08/02/2025.
//

#include <metal_stdlib>
using namespace metal;

struct PointPreviewVertexIn {
    float2 position [[attribute(0)]];
};

struct PointsPreviewTransformUniforms {
    float4x4 transform;
    float4   polygonColor;
};

struct PointsPreviewVSOut {
    float4 position [[position]];
    float4 color;
    float  pointSize [[point_size]];
};

vertex PointsPreviewVSOut vs_points_preview(
    PointPreviewVertexIn inVertex [[stage_in]],
    constant PointsPreviewTransformUniforms &uniforms [[buffer(1)]]
)
{
    PointsPreviewVSOut out;
    
    float4 pos = float4(inVertex.position, 0.0, 1.0);
    pos = uniforms.transform * pos;

    out.position = pos;

    out.color    = uniforms.polygonColor;

    out.pointSize = 8.0;
    return out;
}

fragment float4 fs_points_preview(PointsPreviewVSOut inFrag [[stage_in]])
{
    return inFrag.color;
}
