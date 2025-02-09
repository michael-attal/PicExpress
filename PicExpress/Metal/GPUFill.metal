//
//  GPUFill.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

// BONUS: Fill on gpu manually

#include <metal_stdlib>
using namespace metal;

/// Put a limit
#define MAX_POLY_SIZE 128

struct FillPolygonVertexIn {
    float2 position;  // en clip space [-1..1]
};

struct PolygonData {
    // Effective number of vertices
    uint count;
    // Vertices (x,y)
    float2 pts[MAX_POLY_SIZE];

    // bounding box min / max
    float2 bbMin;
    float2 bbMax;

    float4 fillColor;
};

/// For fragment shader
struct FillPolygonVSOut {
    float4 position [[position]];
    float2 worldPos;
};

vertex FillPolygonVSOut vs_fillPolygon(
    const device FillPolygonVertexIn* inVerts [[buffer(0)]],
    uint vid [[vertex_id]],
    constant PolygonData& poly [[buffer(1)]]
) {
    FillPolygonVSOut out;

    // Recovers quad position in clip space
    float2 clipPos = inVerts[vid].position; // -1..+1
    out.position = float4(clipPos, 0.0, 1.0);

    // Convert clipPos -> range [0..1]
    float2 uv = clipPos * 0.5 + float2(0.5, 0.5);

    // Apply to bounding box
    float2 size = poly.bbMax - poly.bbMin;
    float2 wPos = poly.bbMin + uv * size;

    out.worldPos = wPos;
    return out;
}

fragment float4 fs_fillPolygon(
    FillPolygonVSOut in [[stage_in]],
    constant PolygonData& poly [[buffer(1)]]
) {
    // If not enough vertices => discard
    if (poly.count < 3) {
        discard_fragment();
    }

    // Even-odd parity rule
    float2 p = in.worldPos;
    bool inside = false;
    uint j = poly.count - 1;
    for (uint i = 0; i < poly.count; i++) {
        float2 Pi = poly.pts[i];
        float2 Pj = poly.pts[j];

        // test standard => if intersects
        bool intersect = ((Pi.y > p.y) != (Pj.y > p.y)) &&
                         (p.x < (Pj.x - Pi.x)*(p.y - Pi.y)/(Pj.y - Pi.y) + Pi.x);
        if (intersect) {
            inside = !inside;
        }
        j = i;
    }

    if (inside) {
        return poly.fillColor;
    } else {
        discard_fragment();
    }
}
