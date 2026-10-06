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

/// Clip-space position to pixels relative to the viewport centre.
inline float2 toPixels(float4 clip, float2 viewport) {
    return clip.xy / clip.w * viewport * 0.5;
}

/// Pixels relative to the viewport centre back to clip space, keeping the original depth.
inline float4 fromPixels(float2 px, float4 clip, float2 viewport) {
    return float4(px / (viewport * 0.5) * clip.w, clip.z, clip.w);
}

/// 1 near the camera, falling toward 0 with depth past `fogStart`.
inline float fogFactor(constant MCFrameUniforms& u, float3 worldPosition) {
    float depth = -(u.view * float4(worldPosition, 1.0)).z;
    return exp(-u.fogDensity * max(0.0, depth - u.fogStart));
}

inline float3 acesFitted(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

inline float3 linearToSRGB(float3 c) {
    c = saturate(c);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

#define MC_USES_BOW 0.18   // control-point offset as a fraction of the screen-space chord

struct CurveSample {
    float2 point;
    float2 normal;
};

/// Point and unit normal at t on the quadratic Bézier that bows a uses-edge from pa to pb (pixels).
inline CurveSample usesCurve(float2 pa, float2 pb, float t) {
    float2 delta = pb - pa;
    float len = length(delta);
    float2 dir = len > 1e-3 ? delta / len : float2(1.0, 0.0);
    float2 control = (pa + pb) * 0.5 + float2(-dir.y, dir.x) * (MC_USES_BOW * len);
    float s = 1.0 - t;
    CurveSample sample;
    sample.point = s * s * pa + 2.0 * s * t * control + t * t * pb;
    float2 tangent = 2.0 * s * (control - pa) + 2.0 * t * (pb - control);
    float tangentLength = length(tangent);
    float2 along = tangentLength > 1e-3 ? tangent / tangentLength : dir;
    sample.normal = float2(-along.y, along.x);
    return sample;
}

#endif // MC_SHADER_COMMON_H
