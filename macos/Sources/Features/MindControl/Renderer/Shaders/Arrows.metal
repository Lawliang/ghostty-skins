#include "ShaderCommon.h"

// Arrows are cubic Béziers drawn as triangle strips of (MC_ARROW_SEGMENTS + 1) * 2 vertices.
// Data arrows are solid and carry two pulses travelling from source to target; control arrows are dashed.

constant float kFeatherPoints = 3.0;
constant float kPulseHalfWidth = 6.0;
constant float kPulseOvershoot = 0.25;   // heads run this far past the target (in `along`) while their trails fade

struct ArrowOut {
    float4 position [[position]];
    float3 color;
    float across [[center_no_perspective]];   // pixels from the centreline
    float along;                              // 0 at the source, 1 at the target
    float lengthPx;
    float halfWidth;                          // pixels
    float dashed;
    float seed;
    float time;
    float pixelScale;
    float weight;
};

inline ArrowOut arrowStrip(uint vid, MCArrowInstance a, constant MCFrameUniforms& u, float halfQuadPoints) {
    ArrowOut out = {};
    float t = float(vid / 2) / float(MC_ARROW_SEGMENTS);
    float side = (vid & 1) ? 1.0 : -1.0;
    float2 p = worldToPixels(bezier(a.p0, a.p1, a.p2, a.p3, t), u);
    float2 tangent = bezierTangent(a.p0, a.p1, a.p2, a.p3, t);
    float len = length(tangent);
    float2 dir = len > 1e-4 ? tangent / len : float2(1.0, 0.0);
    float2 normal = float2(-dir.y, dir.x);
    float halfQuad = halfQuadPoints * u.pixelScale;
    out.position = pixelsToClip(p + normal * side * halfQuad, u);
    out.across = side * halfQuad;
    out.along = t;
    out.lengthPx = length(worldToPixels(a.p3, u) - worldToPixels(a.p0, u)) * 1.15;
    out.halfWidth = a.width * 0.5 * u.pixelScale;
    out.color = a.color.rgb;
    out.dashed = a.dashed;
    out.seed = a.seed;
    out.time = u.time;
    out.pixelScale = u.pixelScale;
    return out;
}

vertex ArrowOut mcArrowVertex(uint vid [[vertex_id]],
                              uint iid [[instance_id]],
                              const device MCArrowInstance* arrows [[buffer(MC_BUFFER_INSTANCES)]],
                              constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    MCArrowInstance a = arrows[iid];
    float weight = levelWeight(a.level, u);
    if (weight < 0.01) { ArrowOut out = {}; out.position = culledPosition(); return out; }
    ArrowOut out = arrowStrip(vid, a, u, a.width * 0.5 + kFeatherPoints);
    out.weight = weight;
    return out;
}

fragment float4 mcArrowFragment(ArrowOut in [[stage_in]]) {
    float d = abs(in.across);
    float core = 1.0 - smoothstep(in.halfWidth - 0.75, in.halfWidth + 0.75, d);
    float glow = exp(-d * d / (in.pixelScale * in.pixelScale * 6.0)) * 0.25;
    float dash = in.dashed > 0.5 ? step(0.4, fract(in.along * in.lengthPx / (8.0 * in.pixelScale))) : 1.0;
    return float4(in.color * (core + glow) * dash * in.weight, 0.0);
}

vertex ArrowOut mcPulseVertex(uint vid [[vertex_id]],
                              uint iid [[instance_id]],
                              const device MCArrowInstance* arrows [[buffer(MC_BUFFER_INSTANCES)]],
                              constant MCFrameUniforms& u [[buffer(MC_BUFFER_FRAME)]]) {
    MCArrowInstance a = arrows[iid];
    float weight = levelWeight(a.level, u);
    if (a.pulses < 0.5 || weight < 0.01) { ArrowOut out = {}; out.position = culledPosition(); return out; }
    ArrowOut out = arrowStrip(vid, a, u, kPulseHalfWidth);
    out.weight = weight;
    return out;
}

fragment float4 mcPulseFragment(ArrowOut in [[stage_in]]) {
    float period = mix(2.2, 3.4, hash11(in.seed * 7.3 + 0.1));
    float trail = 0.0;
    for (int k = 0; k < 2; k++) {
        // The head runs on past the target and the pulse fades out there, so its trail slides into the
        // arrowhead instead of vanishing mid-arrow when the head wraps back to the source.
        float head = fract(in.time / period + in.seed + 0.5 * float(k)) * (1.0 + kPulseOvershoot);
        float behind = (head - in.along) * in.lengthPx / in.pixelScale;   // points
        float pulse = behind >= 0.0 ? exp(-behind / 22.0) : exp(behind * 0.8);
        trail += pulse * (1.0 - smoothstep(1.0, 1.0 + kPulseOvershoot, head));
    }
    float across = in.across / in.pixelScale;
    float profile = exp(-across * across * 0.35);
    float ends = smoothstep(0.0, 0.04, in.along) * (1.0 - smoothstep(0.96, 1.0, in.along));
    return float4(in.color * trail * profile * ends * 1.6 * in.weight, 0.0);
}
