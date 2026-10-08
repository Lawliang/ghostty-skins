// Types shared between Swift (via the bridging header) and Metal shaders.
// Keep this file valid C and valid Metal Shading Language.
#ifndef MC_SHADER_TYPES_H
#define MC_SHADER_TYPES_H

#include <simd/simd.h>

#define MC_BUFFER_INSTANCES 0
#define MC_BUFFER_FRAME 1
#define MC_ARROW_SEGMENTS 24   // arrows are cubic Béziers tessellated into this many segments

#define MC_LEVEL_ZONE 0        // drawn when zoomed far out
#define MC_LEVEL_SYSTEM 1
#define MC_LEVEL_PART 2        // drawn when zoomed in
#define MC_LEVEL_ALWAYS 3

#define MC_MARKER_HEAD 0
#define MC_MARKER_DIAMOND 1

typedef struct {
    vector_float2 origin;      // world, top-left
    vector_float2 size;        // world
    vector_float4 fill;        // linear HDR rgb; a unused
    vector_float4 stroke;
    float radius;              // world
    float glow;
    float dashed;              // 1 for external systems
    float level;               // MC_LEVEL_*
} MCBoxInstance;

typedef struct {
    vector_float2 p0;          // world; cubic Bézier control points
    vector_float2 p1;
    vector_float2 p2;
    vector_float2 p3;
    vector_float4 color;
    float width;               // points
    float dashed;
    float pulses;              // 1 draws travelling pulses (data arrows)
    float seed;                // [0, 1)
    float level;               // MC_LEVEL_*
    float pad0;
    float pad1;
    float pad2;
} MCArrowInstance;

typedef struct {
    vector_float2 position;    // world
    vector_float2 direction;   // unit, world
    vector_float4 color;
    float size;                // points
    float shape;               // MC_MARKER_*
    float level;
    float pad;
} MCMarkerInstance;

typedef struct {
    vector_float2 viewportSize;  // drawable pixels
    vector_float2 center;        // world point at the view centre
    float zoom;                  // view points per world point
    float pixelScale;            // backing scale factor
    float time;                  // seconds since launch
    float fixedLevel;            // 1 in focus views: zoom levels don't hide anything
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
