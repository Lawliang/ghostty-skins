// Types shared between Swift (via the bridging header) and Metal shaders.
// Keep this file valid C and valid Metal Shading Language.
#ifndef MC_SHADER_TYPES_H
#define MC_SHADER_TYPES_H

#include <simd/simd.h>

#define MC_BUFFER_INSTANCES 0
#define MC_BUFFER_NODES 1
#define MC_BUFFER_FRAME 2

#define MC_EDGE_CONTAINS 0
#define MC_EDGE_USES 1
#define MC_USES_SEGMENTS 12   // uses-edges are curves tessellated into this many segments

typedef struct {
    vector_float3 position;
    float radius;
    vector_float3 color;   // linear HDR
    float phase;           // radians, desynchronises the pulse
    float intensity;       // brightness multiplier, 0...1
} MCNodeInstance;

typedef struct {
    unsigned int a;
    unsigned int b;
    float signalSeed;      // [0, 1), decides whether and how this edge carries a signal
    unsigned int kind;     // MC_EDGE_CONTAINS or MC_EDGE_USES
} MCEdgeInstance;

typedef struct {
    matrix_float4x4 viewProjection;
    matrix_float4x4 view;
    vector_float2 viewportSize;  // drawable pixels
    float time;                  // seconds since launch
    float pixelScale;            // backing scale factor (pixels per point)
    float fogDensity;
    float fogStart;              // view-space depth where fog begins
    float projScaleY;            // projection[1][1], converts world radius to pixels
    float glowScale;             // 1 for small graphs, lower for dense ones so glows don't saturate
    float usesScale;             // 1 for few uses-edges, lower when there are many so curves don't saturate
} MCFrameUniforms;

typedef struct {
    vector_float2 sourceTexelSize;
    float threshold;
    float knee;
} MCBloomUniforms;

typedef struct {
    vector_float2 viewportSize;
    float time;
    float bloomStrength;
    float exposure;
} MCCompositeUniforms;

#endif // MC_SHADER_TYPES_H
