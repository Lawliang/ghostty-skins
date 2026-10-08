#include "ShaderCommon.h"

// Zones, systems and parts: SDF rounded rectangles with a fill, a crisp stroke and an outer glow.

constant float kGlowPoints = 22.0;
constant float kStrokePoints = 1.1;

struct BoxOut {
    float4 position [[position]];
    float2 local;        // pixels from the box centre
    float2 halfSize;     // pixels
    float radius;        // pixels
    float3 fill;
    float3 stroke;
    float glow;
    float dashed;
    float weight;
    float pixelScale;
};

vertex BoxOut mcBoxVertex(uint vid [[vertex_id]],
                          uint iid [[instance_id]],
                          const device MCBoxInstance* boxes [[buffer(MC_BUFFER_INSTANCES)]],
                          constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    BoxOut out = {};
    MCBoxInstance b = boxes[iid];
    float weight = levelWeight(b.level, u);
    if (weight < 0.01) { out.position = culledPosition(); return out; }

    float2 minPx = worldToPixels(b.origin, u);
    float2 maxPx = worldToPixels(b.origin + b.size, u);
    float2 centre = (minPx + maxPx) * 0.5;
    float2 halfSize = (maxPx - minPx) * 0.5;
    float2 local = quadCorner(vid) * (halfSize + kGlowPoints * u.pixelScale);

    out.position = pixelsToClip(centre + local, u);
    out.local = local;
    out.halfSize = halfSize;
    out.radius = min(b.radius * u.zoom * u.pixelScale, min(halfSize.x, halfSize.y));
    out.fill = b.fill.rgb;
    out.stroke = b.stroke.rgb;
    out.glow = b.glow;
    out.dashed = b.dashed;
    out.weight = weight;
    out.pixelScale = u.pixelScale;
    return out;
}

inline float roundedBox(float2 p, float2 halfSize, float r) {
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

fragment float4 mcBoxFragment(BoxOut in [[stage_in]]) {
    float d = roundedBox(in.local, in.halfSize, in.radius);   // pixels, negative inside
    float inside = 1.0 - smoothstep(-1.0, 1.0, d);
    float strokeHalf = kStrokePoints * in.pixelScale * 0.5;
    float stroke = 1.0 - smoothstep(strokeHalf - 1.0, strokeHalf + 1.0, abs(d));
    if (in.dashed > 0.5) {
        stroke *= step(0.45, fract((in.local.x + in.local.y) / (9.0 * in.pixelScale)));
    }
    float outside = max(d, 0.0) / in.pixelScale;
    // Fades to nothing by the quad's edge, so the halo never ends in a visible rim.
    float reach = 1.0 - smoothstep(kGlowPoints * 0.5, kGlowPoints, outside);
    float glow = exp(-outside / 7.0) * reach * (1.0 - inside) * in.glow * 0.35;
    float3 rgb = in.fill * inside + in.stroke * (stroke * 1.4 + glow);
    return float4(rgb * in.weight, 0.0);
}
