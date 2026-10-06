#include "ShaderCommon.h"

// Neurons: a crisp SDF core inside a breathing halo, plus a faint ring that ripples outward.

constant float kHaloScale = 4.0;        // quad half-size in core radii
constant float kMinCorePoints = 1.4;    // distant nodes never shrink below this

struct NodeOut {
    float4 position [[position]];
    float2 uv;                // offset from centre, in core radii
    float coreRadiusPx;
    float3 color;
    float phase;
    float intensity;
    float fog;
};

vertex NodeOut mcNodeVertex(uint vid [[vertex_id]],
                          uint iid [[instance_id]],
                          const device MCNodeInstance* nodes [[buffer(MC_BUFFER_INSTANCES)]],
                          constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    NodeOut out = {};
    MCNodeInstance n = nodes[iid];
    float4 clip = u.viewProjection * float4(n.position, 1.0);
    if (clip.w < 0.01) { out.position = culledPosition(); return out; }

    float radiusPx = n.radius * u.projScaleY / clip.w * u.viewportSize.y * 0.5;
    radiusPx = max(radiusPx, kMinCorePoints * u.pixelScale);

    float2 corner = quadCorner(vid) * kHaloScale;
    out.position = fromPixels(toPixels(clip, u.viewportSize) + corner * radiusPx, clip, u.viewportSize);
    out.uv = corner;
    out.coreRadiusPx = radiusPx;
    out.color = n.color;
    out.intensity = n.intensity;
    out.phase = n.phase;
    out.fog = fogFactor(u, n.position);
    return out;
}

fragment float4 mcNodeFragment(NodeOut in [[stage_in]],
                             constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float r = length(in.uv);
    float aa = 1.0 / max(in.coreRadiusPx, 1.0);
    float core = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);

    float breathe = 0.5 + 0.5 * sin(u.time * 1.4 + in.phase);
    float halo = exp(-r * r * 0.7) * (0.25 + 0.55 * breathe) + exp(-r * 1.4) * 0.12;

    float wave = fract(u.time * 0.22 + in.phase * 0.159);
    float ringRadius = 1.0 + wave * (kHaloScale - 1.4);
    float ring = exp(-pow((r - ringRadius) * 5.0, 2.0)) * (1.0 - wave) * 0.22;

    float edgeFade = 1.0 - smoothstep(kHaloScale * 0.75, kHaloScale, r);
    float3 coreColor = mix(in.color, float3(1.0), 0.7) * 2.4 * mix(0.4, 1.0, u.glowScale);
    float3 glow = in.color * (halo + ring) * edgeFade * u.glowScale;
    float3 rgb = coreColor * core + glow * (1.0 - core);
    return float4(rgb * in.intensity * in.fog, 0.0);
}
