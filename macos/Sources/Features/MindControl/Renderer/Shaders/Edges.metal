#include "ShaderCommon.h"

// Hairline edges: a quad expanded in screen space to a constant pixel width,
// with an anti-aliased core and a faint glow.

constant float kEdgeHalfWidth = 0.6;   // core half-width, points
constant float kEdgeFeather = 1.6;     // extra quad half-width for AA and glow, points

struct EdgeOut {
    float4 position [[position]];
    float3 color;
    float across [[center_no_perspective]];  // pixels from the centreline
    float fog;
};

vertex EdgeOut mcEdgeVertex(uint vid [[vertex_id]],
                          uint iid [[instance_id]],
                          const device MCEdgeInstance* edges [[buffer(MC_BUFFER_INSTANCES)]],
                          const device MCNodeInstance* nodes [[buffer(MC_BUFFER_NODES)]],
                          constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    EdgeOut out = {};
    MCEdgeInstance e = edges[iid];
    MCNodeInstance na = nodes[e.a];
    MCNodeInstance nb = nodes[e.b];

    float4 ca = u.viewProjection * float4(na.position, 1.0);
    float4 cb = u.viewProjection * float4(nb.position, 1.0);
    if (ca.w < 0.01 || cb.w < 0.01) { out.position = culledPosition(); return out; }

    float2 pa = toPixels(ca, u.viewportSize);
    float2 pb = toPixels(cb, u.viewportSize);
    float2 delta = pb - pa;
    float len = length(delta);
    float2 dir = len > 1e-3 ? delta / len : float2(1.0, 0.0);
    float2 normal = float2(-dir.y, dir.x);

    bool atB = vid >= 2;
    float side = (vid & 1) ? 1.0 : -1.0;
    float halfQuad = (kEdgeHalfWidth + kEdgeFeather) * u.pixelScale;

    float4 clip = atB ? cb : ca;
    float2 px = (atB ? pb : pa) + normal * side * halfQuad;
    out.position = fromPixels(px, clip, u.viewportSize);
    out.color = (atB ? nb.color : na.color) * min(na.intensity, nb.intensity);
    out.across = side * halfQuad;
    out.fog = fogFactor(u, atB ? nb.position : na.position);
    return out;
}

fragment float4 mcEdgeFragment(EdgeOut in [[stage_in]],
                             constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float d = abs(in.across) / u.pixelScale;  // points from centreline
    float core = 1.0 - smoothstep(kEdgeHalfWidth - 0.5, kEdgeHalfWidth + 0.5, d);
    float glow = exp(-d * d * 0.7);
    float intensity = (core * 0.30 + glow * 0.10) * u.glowScale;
    return float4(in.color * intensity * in.fog, 0.0);
}
