//
//  Shaders.metal
//  HelloMetal001
//
//  Created by Yoshiki Izumi on 2019/12/28.
//  Copyright © 2019 Yoshiki Izumi. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shawhite_edge between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

struct InOut {
    float4 position [[position]];
    float4 color;
    float3 normal;
};

struct InOutTex {
    float2 texCoords;
};

struct InOut2 {
    float4 position [[position]];
    float4 color;
    float3 normal;
    float3 light;
    float2 texCoords;
};

vertex InOut2 vertexShader(constant InOut *vertices [[buffer(0)]],
                          uint vid [[vertex_id]],
                          constant Uniforms & uniforms [[ buffer(1) ]],
                           constant InOutTex *tex [[buffer(2)]]
                          ) {
    InOut2 out;
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * (vertices[vid].position);
    out.color = vertices[vid].color;
    out.normal = ( uniforms.projectionMatrix * uniforms.modelViewMatrix * float4(vertices[vid].normal.xyz, 1.0) ).xyz;
    out.light = uniforms.lightPosition;
    out.texCoords = tex[vid].texCoords;
    return out;
}


fragment float4 fragmentShader(InOut2 vert [[stage_in]]) {
    float3 n;
        n.xy = vert.texCoords.xy * 2.0 - 1.0;
        n.z  = 1.0 - dot(n.xy, n.xy);
        if (n.z < 0.0) { discard_fragment(); }
    float4 fragColor = vert.color;
        fragColor.a = (1.0 - cos(n.z * 2.0)) / 4.0 + 0.65;
    //    fragColor.r = pow(fragColor.r, 4.0);
    //    fragColor.g = pow(fragColor.g, 4.0);
    //    fragColor.b = pow(fragColor.b, 4.0);
        fragColor.a = pow(fragColor.a, 16.0);
        return fragColor;

//    float3 lightColor = float3(0.1, 0.1, 0.1);
//    float3 halfway = normalize(vert.light.xyz + vert.position.xyz);
//    float specular = pow(max(dot(vert.normal, halfway), 0.0), 5);
//    float directional = max(dot(normalize(vert.light) , vert.normal), 0.0);
//    float3 vLighting = vert.color.rgb + (lightColor * (directional + specular));
//    return float4(vLighting, vert.color.a);
}
