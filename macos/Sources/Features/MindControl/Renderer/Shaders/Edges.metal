#include "ShaderCommon.h"

// Contains-edges: straight hairlines in a neutral blue-grey — the folder skeleton.
// Uses-edges: amber quadratic Bézier curves — one file depends on another.

constant float kContainsHalfWidth = 0.25;   // core half-width, points
constant float kUsesHalfWidth = 0.45;       // core half-width, points
constant float kFeather = 1.6;              // extra quad half-width for AA and glow, points
constant float3 kContainsColor = float3(0.42, 0.52, 0.78);
constant float3 kUsesColor = float3(1.0, 0.68, 0.30);

struct EdgeOut {
    float4 position [[position]];
    float3 color;
    float across [[center_no_perspective]];   // pixels from the centreline
    float fog;
};

vertex EdgeOut mcContainsEdgeVertex(uint vid [[vertex_id]],
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
    float halfQuad = (kContainsHalfWidth + kFeather) * u.pixelScale;

    float4 clip = atB ? cb : ca;
    out.position = fromPixels((atB ? pb : pa) + normal * side * halfQuad, clip, u.viewportSize);
    out.color = kContainsColor * min(na.intensity, nb.intensity);
    out.across = side * halfQuad;
    out.fog = fogFactor(u, atB ? nb.position : na.position);
    return out;
}

fragment float4 mcContainsEdgeFragment(EdgeOut in [[stage_in]],
                                       constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float d = abs(in.across) / u.pixelScale;
    float core = 1.0 - smoothstep(kContainsHalfWidth - 0.5, kContainsHalfWidth + 0.5, d);
    float glow = exp(-d * d * 0.7);
    float intensity = (core * 0.15 + glow * 0.05) * u.glowScale;
    return float4(in.color * intensity * in.fog, 0.0);
}

/// Uses-edges are triangle strips of (MC_USES_SEGMENTS + 1) * 2 vertices following usesCurve.
vertex EdgeOut mcUsesEdgeVertex(uint vid [[vertex_id]],
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

    float t = float(vid / 2) / float(MC_USES_SEGMENTS);
    float side = (vid & 1) ? 1.0 : -1.0;
    CurveSample c = usesCurve(toPixels(ca, u.viewportSize), toPixels(cb, u.viewportSize), t);
    float halfQuad = (kUsesHalfWidth + kFeather) * u.pixelScale;

    out.position = fromPixels(c.point + c.normal * side * halfQuad, mix(ca, cb, t), u.viewportSize);
    out.color = kUsesColor * min(na.intensity, nb.intensity);
    out.across = side * halfQuad;
    out.fog = mix(fogFactor(u, na.position), fogFactor(u, nb.position), t);
    return out;
}

fragment float4 mcUsesEdgeFragment(EdgeOut in [[stage_in]],
                                   constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float d = abs(in.across) / u.pixelScale;
    float core = 1.0 - smoothstep(kUsesHalfWidth - 0.5, kUsesHalfWidth + 0.5, d);
    float glow = exp(-d * d * 0.5);
    float intensity = (core * 0.45 + glow * 0.15) * u.glowScale * u.usesScale;
    return float4(in.color * intensity * in.fog, 0.0);
}
