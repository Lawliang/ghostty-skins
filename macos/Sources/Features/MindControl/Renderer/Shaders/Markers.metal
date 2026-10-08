#include "ShaderCommon.h"

// Arrowheads at arrow targets and diamonds where a conditional arrow leaves its source.

struct MarkerOut {
    float4 position [[position]];
    float2 local;      // marker units: +x along the arrow
    float3 color;
    float shape;
    float weight;
};

vertex MarkerOut mcMarkerVertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device MCMarkerInstance* markers [[buffer(MC_BUFFER_INSTANCES)]],
                                constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    MarkerOut out = {};
    MCMarkerInstance m = markers[iid];
    float weight = levelWeight(m.level, u);
    if (weight < 0.01) { out.position = culledPosition(); return out; }
    float2 dir = length(m.direction) > 1e-4 ? normalize(m.direction) : float2(1.0, 0.0);
    float2 normal = float2(-dir.y, dir.x);
    float2 corner = quadCorner(vid) * 1.6;
    float sizePx = m.size * u.pixelScale;
    out.position = pixelsToClip(worldToPixels(m.position, u) + (dir * corner.x + normal * corner.y) * sizePx, u);
    out.local = corner;
    out.color = m.color.rgb;
    out.shape = m.shape;
    out.weight = weight;
    return out;
}

fragment float4 mcMarkerFragment(MarkerOut in [[stage_in]]) {
    float2 p = in.local;
    float d;
    if (in.shape < 0.5) {
        // Arrowhead: tip at the origin pointing +x, base 1.4 units back, 0.8 half-width at the base.
        d = max(max(p.x, -1.4 - p.x), abs(p.y) - 0.8 * (-p.x) / 1.4);
    } else {
        d = abs(p.x) + abs(p.y) - 0.9;
    }
    float shape = 1.0 - smoothstep(-0.08, 0.08, d);
    return float4(in.color * shape * 1.3 * in.weight, 0.0);
}
