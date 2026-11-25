// AetherShaders.metal
// AetherWin - Metal 3 Fullscreen Triangle & Contrast-Adaptive Sharpening (CAS) Shaders
// Optimized for Apple A15 Bionic 4-Core GPU (FP16 / Half-Precision Alu Paths)

#include <metal_stdlib>
using namespace metal;

struct FullscreenVertexOut {
    float4 position [[position]];
    float2 uv;
};

// Generates a single fullscreen triangle with zero vertex buffer overhead
vertex FullscreenVertexOut aether_fullscreen_vertex(uint vertexID [[vertex_id]]) {
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    FullscreenVertexOut out;
    out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    out.uv = uv;
    return out;
}

// AMD FidelityFX-inspired Contrast Adaptive Sharpening (CAS) in fast A15 FP16 half-precision
fragment half4 aether_cas_present_fragment(FullscreenVertexOut in [[stage_in]],
                                           texture2d<half> sourceTex [[texture(0)]],
                                           sampler linearSampler [[sampler(0)]],
                                           constant float &sharpness [[buffer(0)]]) {
    float2 texel = 1.0 / float2(sourceTex.get_width(), sourceTex.get_height());

    half3 c = sourceTex.sample(linearSampler, in.uv).rgb;
    half3 n = sourceTex.sample(linearSampler, in.uv + float2(0.0, -texel.y)).rgb;
    half3 s = sourceTex.sample(linearSampler, in.uv + float2(0.0,  texel.y)).rgb;
    half3 w = sourceTex.sample(linearSampler, in.uv + float2(-texel.x, 0.0)).rgb;
    half3 e = sourceTex.sample(linearSampler, in.uv + float2( texel.x, 0.0)).rgb;

    half k = half(sharpness) * 0.25h;
    half3 result = saturate(c + (c * 4.0h - (n + s + w + e)) * k);
    return half4(result, 1.0h);
}
