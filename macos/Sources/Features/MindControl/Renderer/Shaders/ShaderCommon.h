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

// Swift reads and writes these structs with the C layout (FlowSceneTests pins the same sizes there).
static_assert(sizeof(MCBoxInstance) == 64, "MCBoxInstance layout");
static_assert(sizeof(MCArrowInstance) == 80, "MCArrowInstance layout");
static_assert(sizeof(MCMarkerInstance) == 48, "MCMarkerInstance layout");
static_assert(sizeof(MCFrameUniforms) == 32, "MCFrameUniforms layout");

/// World point → drawable pixels, top-left origin. Matches PanZoomCamera.toScreen × pixelScale.
inline float2 worldToPixels(float2 p, constant MCFrameUniforms& u) {
    return (p - u.center) * u.zoom * u.pixelScale + u.viewportSize * 0.5;
}

inline float4 pixelsToClip(float2 px, constant MCFrameUniforms& u) {
    return float4(px.x / u.viewportSize.x * 2.0 - 1.0, 1.0 - px.y / u.viewportSize.y * 2.0, 0.0, 1.0);
}

/// How visible something at `level` is at the current zoom. Mirrors MindControl.ZoomLevels.
inline float levelWeight(float level, constant MCFrameUniforms& u) {
    if (u.fixedLevel > 0.5 || level > 2.5) return 1.0;
    float toSystems = smoothstep(0.22, 0.34, u.zoom);
    float toParts = smoothstep(0.85, 1.15, u.zoom);
    if (level < 0.5) return 1.0 - toSystems;
    if (level < 1.5) return toSystems * (1.0 - toParts);
    return toParts;
}

inline float2 bezier(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
    float s = 1.0 - t;
    return s * s * s * p0 + 3.0 * s * s * t * p1 + 3.0 * s * t * t * p2 + t * t * t * p3;
}

inline float2 bezierTangent(float2 p0, float2 p1, float2 p2, float2 p3, float t) {
    float s = 1.0 - t;
    return 3.0 * s * s * (p1 - p0) + 6.0 * s * t * (p2 - p1) + 3.0 * t * t * (p3 - p2);
}

#endif // MC_SHADER_COMMON_H
