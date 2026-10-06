#include "ShaderCommon.h"

vertex FullscreenOut mcFullscreenVertex(uint vid [[vertex_id]]) {
    // One oversized triangle covering the screen: (-1,-1), (3,-1), (-1,3).
    float2 pos = float2((vid << 1) & 2, vid & 2) * 2.0 - 1.0;
    FullscreenOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = float2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5);
    return out;
}

fragment float4 mcCompositeFragment(FullscreenOut in [[stage_in]],
                                  texture2d<float> scene [[texture(0)]],
                                  texture2d<float> bloom [[texture(1)]],
                                  constant MCCompositeUniforms& c [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float aspect = c.viewportSize.x / max(c.viewportSize.y, 1.0);
    float radial = length((in.uv - 0.5) * float2(aspect, 1.0));

    // Deep blue-black, lifted toward indigo at the centre (linear values).
    float3 background = mix(float3(0.010, 0.009, 0.034), float3(0.0009, 0.0012, 0.0033), smoothstep(0.0, 0.95, radial));

    float3 hdr = scene.sample(s, in.uv).rgb;
    float3 glow = bloom.sample(s, in.uv).rgb;
    float3 color = (background + hdr + glow * c.bloomStrength) * c.exposure;

    color = acesFitted(color);
    color *= mix(1.0, 1.0 - smoothstep(0.25, 1.15, radial), 0.45);   // vignette
    color = linearToSRGB(color);

    // Sub-LSB noise breaks up banding in the dark gradient.
    float noise = hash21(in.position.xy + fract(c.time) * 61.0) - 0.5;
    color += noise / 255.0;
    return float4(saturate(color), 1.0);
}
