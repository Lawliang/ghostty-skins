// Types shared between Swift (via the bridging header) and Metal shaders.
// Keep this file valid C and valid Metal Shading Language.
#ifndef MC_SHADER_TYPES_H
#define MC_SHADER_TYPES_H

#include <simd/simd.h>

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
