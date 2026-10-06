#include "ShaderCommon.h"

// Faint motes in a distant shell around the graph. Instance data: xyz position, w brightness.

struct DustOut {
    float4 position [[position]];
    float2 uv;
    float brightness;
};

vertex DustOut mcDustVertex(uint vid [[vertex_id]],
                          uint iid [[instance_id]],
                          const device float4* dust [[buffer(MC_BUFFER_INSTANCES)]],
                          constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    DustOut out = {};
    float4 d = dust[iid];
    float4 clip = u.viewProjection * float4(d.xyz, 1.0);
    if (clip.w < 0.01) { out.position = culledPosition(); return out; }

    float2 corner = quadCorner(vid);
    float sizePx = (0.9 + d.w * 1.3) * u.pixelScale;
    out.position = fromPixels(toPixels(clip, u.viewportSize) + corner * sizePx, clip, u.viewportSize);
    out.uv = corner;
    out.brightness = d.w;
    return out;
}

fragment float4 mcDustFragment(DustOut in [[stage_in]],
                             constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float falloff = exp(-dot(in.uv, in.uv) * 3.0);
    float twinkle = 0.75 + 0.25 * sin(u.time * 0.7 + in.brightness * 40.0);
    float3 tint = float3(0.35, 0.45, 0.95);
    return float4(tint * 0.18 * in.brightness * falloff * twinkle, 0.0);
}
