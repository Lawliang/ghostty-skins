#include "ShaderCommon.h"

// Signals travel along uses-edges from the file that uses something toward its definition,
// following the same curve. Derived from the edge seed and time: no per-frame CPU work.

constant float kCarryChance = 0.4;       // fraction of uses-edges that carry a signal when there are few
constant float kSignalHalfWidth = 5.0;   // quad half-width, points
constant float kTailPoints = 60.0;       // tail length scale, points
constant float3 kSignalColor = float3(1.0, 0.86, 0.62);

struct SignalOut {
    float4 position [[position]];
    float3 color;
    float along [[center_no_perspective]];    // 0 at the user, 1 at the definition
    float across [[center_no_perspective]];   // points from the centreline
    float lengthPoints;
    float head;
    float fog;
};

vertex SignalOut mcSignalVertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device MCEdgeInstance* edges [[buffer(MC_BUFFER_INSTANCES)]],
                                const device MCNodeInstance* nodes [[buffer(MC_BUFFER_NODES)]],
                                constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    SignalOut out = {};
    MCEdgeInstance e = edges[iid];
    // Many edges → proportionally fewer signals, so the number in flight stays roughly constant.
    float carryChance = kCarryChance * u.usesScale * u.usesScale;
    if (hash11(e.signalSeed * 13.7 + 0.5) > carryChance) { out.position = culledPosition(); return out; }

    MCNodeInstance na = nodes[e.a];
    MCNodeInstance nb = nodes[e.b];
    float4 ca = u.viewProjection * float4(na.position, 1.0);
    float4 cb = u.viewProjection * float4(nb.position, 1.0);
    if (ca.w < 0.01 || cb.w < 0.01) { out.position = culledPosition(); return out; }

    float2 pa = toPixels(ca, u.viewportSize);
    float2 pb = toPixels(cb, u.viewportSize);
    float chord = length(pb - pa);
    if (chord < 1.0) { out.position = culledPosition(); return out; }

    float t = float(vid / 2) / float(MC_USES_SEGMENTS);
    float side = (vid & 1) ? 1.0 : -1.0;
    CurveSample c = usesCurve(pa, pb, t);
    float halfQuad = kSignalHalfWidth * u.pixelScale;

    out.position = fromPixels(c.point + c.normal * side * halfQuad, mix(ca, cb, t), u.viewportSize);
    out.along = t;
    out.across = side * kSignalHalfWidth;
    out.lengthPoints = chord * 1.05 / u.pixelScale;   // the bow adds a few percent of length

    float period = mix(2.5, 6.0, hash11(e.signalSeed * 3.1 + 2.3));
    out.head = fract(u.time / period + e.signalSeed) * 1.8 - 0.2;
    out.color = kSignalColor * min(na.intensity, nb.intensity);
    out.fog = mix(fogFactor(u, na.position), fogFactor(u, nb.position), t);
    return out;
}

fragment float4 mcSignalFragment(SignalOut in [[stage_in]],
                                 constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    float behind = (in.head - in.along) * in.lengthPoints;
    float trail = behind >= 0.0 ? exp(-behind / kTailPoints * 3.0) : exp(behind * 0.9);
    float profile = exp(-in.across * in.across * 0.45);
    float spark = exp(-(behind * behind + in.across * in.across) * 0.2);
    float onEdge = smoothstep(0.0, 0.03, in.along) * (1.0 - smoothstep(0.97, 1.0, in.along));
    float intensity = (trail * profile * 1.4 + spark * 3.5) * onEdge * mix(0.5, 1.0, u.glowScale) * mix(0.25, 1.0, u.usesScale);
    return float4(in.color * intensity * in.fog, 0.0);
}
