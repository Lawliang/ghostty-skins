#include "ShaderCommon.h"

// Signals: bright heads with exponential tails travelling along a subset of edges.
// Everything is derived from the edge seed and time, so the CPU does no per-frame work.

constant float kCarryChance = 0.4;     // fraction of edges that carry a signal
constant float kSignalHalfWidth = 5.0; // quad half-width, points
constant float kTailPoints = 60.0;     // tail length scale, points

struct SignalOut {
    float4 position [[position]];
    float3 color;
    float along [[center_no_perspective]];   // 0 at source, 1 at destination
    float across [[center_no_perspective]];  // points from centreline
    float lengthPoints;
    float head;                              // head position along the edge
    float fog;
};

vertex SignalOut mcSignalVertex(uint vid [[vertex_id]],
                              uint iid [[instance_id]],
                              const device MCEdgeInstance* edges [[buffer(MC_BUFFER_INSTANCES)]],
                              const device MCNodeInstance* nodes [[buffer(MC_BUFFER_NODES)]],
                              constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    SignalOut out = {};
    MCEdgeInstance e = edges[iid];
    if (hash11(e.signalSeed * 13.7 + 0.5) > kCarryChance) { out.position = culledPosition(); return out; }

    bool reverse = hash11(e.signalSeed * 7.3 + 1.1) < 0.5;
    MCNodeInstance na = nodes[reverse ? e.b : e.a];
    MCNodeInstance nb = nodes[reverse ? e.a : e.b];

    float4 ca = u.viewProjection * float4(na.position, 1.0);
    float4 cb = u.viewProjection * float4(nb.position, 1.0);
    if (ca.w < 0.01 || cb.w < 0.01) { out.position = culledPosition(); return out; }

    float2 pa = toPixels(ca, u.viewportSize);
    float2 pb = toPixels(cb, u.viewportSize);
    float2 delta = pb - pa;
    float len = length(delta);
    if (len < 1.0) { out.position = culledPosition(); return out; }
    float2 dir = delta / len;
    float2 normal = float2(-dir.y, dir.x);

    bool atB = vid >= 2;
    float side = (vid & 1) ? 1.0 : -1.0;
    float halfQuad = kSignalHalfWidth * u.pixelScale;

    float4 clip = atB ? cb : ca;
    out.position = fromPixels((atB ? pb : pa) + normal * side * halfQuad, clip, u.viewportSize);
    out.along = atB ? 1.0 : 0.0;
    out.across = side * kSignalHalfWidth;
    out.lengthPoints = len / u.pixelScale;

    // Each signal travels the edge, then rests off-edge for part of its period.
    float period = mix(2.5, 6.0, hash11(e.signalSeed * 3.1 + 2.3));
    float cycle = fract(u.time / period + e.signalSeed);
    out.head = cycle * 1.8 - 0.2;

    out.color = mix(atB ? nb.color : na.color, float3(0.75, 0.92, 1.0), 0.55);
    out.fog = fogFactor(u, atB ? nb.position : na.position);
    return out;
}

fragment float4 mcSignalFragment(SignalOut in [[stage_in]]) {
    float behind = (in.head - in.along) * in.lengthPoints;   // points behind the head; negative is ahead
    float trail = behind >= 0.0 ? exp(-behind / kTailPoints * 3.0) : exp(behind * 0.9);
    float across = in.across;
    float profile = exp(-across * across * 0.45);
    float spark = exp(-(behind * behind + across * across) * 0.2);

    // Keep the signal on the edge itself; it vanishes into the destination node.
    float onEdge = smoothstep(0.0, 0.03, in.along) * (1.0 - smoothstep(0.97, 1.0, in.along));
    float intensity = (trail * profile * 1.4 + spark * 3.5) * onEdge;
    return float4(in.color * intensity * in.fog, 0.0);
}
