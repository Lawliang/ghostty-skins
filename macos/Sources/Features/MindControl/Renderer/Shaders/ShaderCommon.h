// Helpers shared by every .metal file. Each .metal file is its own translation unit,
// so everything here is `inline`.
#ifndef MC_SHADER_COMMON_H
#define MC_SHADER_COMMON_H

#include <metal_stdlib>
#include "../ShaderTypes.h"
using namespace metal;

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

/// Triangle-strip corner for vertex 0...3: (-1,-1), (1,-1), (-1,1), (1,1).
inline float2 quadCorner(uint vid) {
    return float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
}

/// Off-screen position used to cull a primitive from the vertex shader.
inline float4 culledPosition() { return float4(2.0, 2.0, 2.0, 1.0); }

inline float hash11(float x) { return fract(sin(x * 127.1) * 43758.5453); }
inline float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

inline float3 acesFitted(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

inline float3 linearToSRGB(float3 c) {
    c = saturate(c);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

#endif // MC_SHADER_COMMON_H
