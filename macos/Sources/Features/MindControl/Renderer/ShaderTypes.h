// Types shared between Swift (via the bridging header) and Metal shaders.
// Keep this file valid C and valid Metal Shading Language.
#ifndef MC_SHADER_TYPES_H
#define MC_SHADER_TYPES_H

#include <simd/simd.h>

#define MC_BUFFER_INSTANCES 0
#define MC_BUFFER_NODES 1
#define MC_BUFFER_FRAME 2

typedef struct {
    vector_float3 position;
    float radius;
    vector_float3 color;   // linear HDR
    float phase;           // radians, desynchronises the pulse
} MCNodeInstance;

typedef struct {
    unsigned int a;
    unsigned int b;
    float signalSeed;      // [0, 1), decides whether and how this edge carries a signal
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
