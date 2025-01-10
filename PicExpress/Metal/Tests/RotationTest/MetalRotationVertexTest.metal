//
//  MetalRotationVertexTest.metal
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

#include <metal_stdlib>
using namespace metal;

struct RotationTestVertexIn {
   float3 position [[attribute(0)]];
   float4 color [[attribute(1)]];
};

struct RotationTestVertexOut {
   float4 position [[position]];
   float4 color;
};

vertex RotationTestVertexOut vertex_rotation_test(const device RotationTestVertexIn* vertexArray [[buffer(0)]],
                            uint vertexID [[vertex_id]],
                            constant float4x4& modelViewProjectionMatrix [[buffer(1)]]) {
    RotationTestVertexOut out;
   float3 position = vertexArray[vertexID].position;
   out.position = modelViewProjectionMatrix * float4(position, 1.0);
   out.color = vertexArray[vertexID].color;
   return out;
}

fragment float4 fragment_rotation_test(RotationTestVertexOut in [[stage_in]]) {
   return in.color;
}
