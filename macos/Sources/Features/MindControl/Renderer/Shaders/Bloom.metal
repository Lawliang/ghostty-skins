#include "ShaderCommon.h"

// Mip-chain bloom: a 13-tap downsample (prefiltered on the first level),
// then 9-tap tent upsamples blended additively back up the chain.

constexpr sampler bloomSampler(filter::linear, address::clamp_to_edge);

inline float3 downsample13(texture2d<float> t, float2 uv, float2 ts) {
    float3 a = t.sample(bloomSampler, uv + ts * float2(-2,  2)).rgb;
    float3 b = t.sample(bloomSampler, uv + ts * float2( 0,  2)).rgb;
    float3 c = t.sample(bloomSampler, uv + ts * float2( 2,  2)).rgb;
    float3 d = t.sample(bloomSampler, uv + ts * float2(-2,  0)).rgb;
    float3 e = t.sample(bloomSampler, uv).rgb;
    float3 f = t.sample(bloomSampler, uv + ts * float2( 2,  0)).rgb;
    float3 g = t.sample(bloomSampler, uv + ts * float2(-2, -2)).rgb;
    float3 h = t.sample(bloomSampler, uv + ts * float2( 0, -2)).rgb;
    float3 i = t.sample(bloomSampler, uv + ts * float2( 2, -2)).rgb;
    float3 j = t.sample(bloomSampler, uv + ts * float2(-1,  1)).rgb;
    float3 k = t.sample(bloomSampler, uv + ts * float2( 1,  1)).rgb;
    float3 l = t.sample(bloomSampler, uv + ts * float2(-1, -1)).rgb;
    float3 m = t.sample(bloomSampler, uv + ts * float2( 1, -1)).rgb;
    return e * 0.125
         + (a + c + g + i) * 0.03125
         + (b + d + f + h) * 0.0625
         + (j + k + l + m) * 0.125;
}

fragment float4 mcBloomPrefilter(FullscreenOut in [[stage_in]],
                               texture2d<float> source [[texture(0)]],
                               constant MCBloomUniforms& b [[buffer(0)]]) {
    float3 color = downsample13(source, in.uv, b.sourceTexelSize);
    // Soft-knee threshold: only light brighter than ~threshold blooms, with a smooth ramp.
    float brightness = max(color.r, max(color.g, color.b));
    float soft = clamp(brightness - b.threshold + b.knee, 0.0, 2.0 * b.knee);
    soft = soft * soft / (4.0 * b.knee + 1e-5);
    float contribution = max(soft, brightness - b.threshold) / max(brightness, 1e-5);
    return float4(color * contribution, 1.0);
}

fragment float4 mcBloomDownsample(FullscreenOut in [[stage_in]],
                                texture2d<float> source [[texture(0)]],
                                constant MCBloomUniforms& b [[buffer(0)]]) {
    return float4(downsample13(source, in.uv, b.sourceTexelSize), 1.0);
}

fragment float4 mcBloomUpsample(FullscreenOut in [[stage_in]],
                              texture2d<float> source [[texture(0)]],
                              constant MCBloomUniforms& b [[buffer(0)]]) {
    float2 ts = b.sourceTexelSize;
    float2 uv = in.uv;
    float3 sum = source.sample(bloomSampler, uv).rgb * 4.0;
    sum += (source.sample(bloomSampler, uv + ts * float2( 0,  1)).rgb
          + source.sample(bloomSampler, uv + ts * float2( 0, -1)).rgb
          + source.sample(bloomSampler, uv + ts * float2( 1,  0)).rgb
          + source.sample(bloomSampler, uv + ts * float2(-1,  0)).rgb) * 2.0;
    sum += source.sample(bloomSampler, uv + ts * float2( 1,  1)).rgb
         + source.sample(bloomSampler, uv + ts * float2(-1,  1)).rgb
         + source.sample(bloomSampler, uv + ts * float2( 1, -1)).rgb
         + source.sample(bloomSampler, uv + ts * float2(-1, -1)).rgb;
    return float4(sum / 16.0, 1.0);
}
