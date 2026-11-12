// WaveBlob.metal — audio-reactive "Моя волна" backdrop.
//
// Drawn by `WaveRenderer` into a deliberately tiny CAMetalLayer drawable (~120×200 px) that
// Core Animation stretches over the hero. The field is smooth and low-frequency, so the
// upscale is invisible while the fragment load is ~1% of a full-resolution pass.
//
// Each pixel:
//   1. Domain-warps its coordinate with two fbm fields (organic fluid motion), plus a finger
//      "pull" warp toward the touch point.
//   2. Evaluates 4 gaussian metaballs whose centres orbit slowly; bass swells radius, highs
//      ripple the edges.
//   3. Mixes the 4 palette colours in OKLab weighted by each ball's field (no grey midpoints).
//      The palette arrives already converted to OKLab — that used to be 4 pow() chains per pixel.
//   4. Fades into true black around and below the cloud and adds a 1-LSB dither against banding.

#include <metal_stdlib>
using namespace metal;

// Must match `WaveUniforms` in WaveRenderer.swift (same order, same types).
struct WaveUniforms {
    float4 spectrum;   // bass, low-mid, high-mid, treble (0...1, smoothed on the CPU)
    float4 lab0;       // palette in OKLab (xyz), w unused
    float4 lab1;
    float4 lab2;
    float4 lab3;
    float2 size;       // drawable size in pixels
    float2 touch;      // touch point in drawable pixels
    float time;        // seconds, already slowed when paused
    float touchAmt;    // 0...1 touch strength (spring-decayed on the CPU)
    float intensity;   // 0...1 overall energy (lower when paused)
    float dim;         // 0...1 overall brightness multiplier
};

struct WaveVertexOut {
    float4 position [[position]];
};

// Full-screen triangle, no vertex buffer.
vertex WaveVertexOut waveVertex(uint vid [[vertex_id]]) {
    WaveVertexOut out;
    float2 p = float2((vid << 1) & 2, vid & 2);
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// MARK: - Noise

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i), b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1)), d = hash12(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    const float2x2 rot = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 3; i++) {
        v += a * vnoise(p);
        p = rot * p * 2.02 + 17.0;
        a *= 0.5;
    }
    return v;
}

// MARK: - OKLab -> sRGB (Björn Ottosson)

static float3 linearToSrgb(float3 c) {
    c = max(c, 0.0);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

static float3 oklabToLinear(float3 c) {
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l; m = m * m * m; s = s * s * s;
    return float3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                 -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                 -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

// MARK: - Fragment

fragment half4 waveFragment(WaveVertexOut in [[stage_in]], constant WaveUniforms &u [[buffer(0)]]) {
    float2 position = in.position.xy;
    float2 size = max(u.size, float2(1.0));
    float aspect = size.x / size.y;
    // Normalised coords: y in 0...1, x scaled by aspect so blobs stay round.
    float2 uv = position / size.y;
    float2 tuv = u.touch / size.y;

    float bass = u.spectrum.x, lowMid = u.spectrum.y, highMid = u.spectrum.z, treble = u.spectrum.w;
    float time = u.time;
    float t = time * 0.12;

    // Finger pull: pixels near the touch are displaced toward it (gaussian falloff).
    float2 toTouch = tuv - uv;
    float pull = u.touchAmt * exp(-dot(toTouch, toTouch) * 9.0);
    uv += toTouch * pull * 0.45;

    // Two-level domain warp (Inigo Quilez style) for fluid, non-circular shapes.
    float2 q = float2(fbm(uv * 1.6 + float2(0.0, t)), fbm(uv * 1.6 + float2(5.2, -t * 0.8)));
    float2 r = float2(fbm(uv * 2.0 + q * 2.2 + float2(1.7, 9.2) + t * 0.6),
                      fbm(uv * 2.0 + q * 2.2 + float2(8.3, 2.8) - t * 0.5));
    // Highs add a fine shimmer ripple on top of the warp.
    float ripple = sin((uv.x + uv.y) * 38.0 - time * 3.0) * (highMid * 0.5 + treble) * 0.006;
    float2 w = uv + (r - 0.5) * (0.28 + lowMid * 0.12) + ripple;

    // Metaball centres orbit in the upper ~60% of the view.
    float2 centre = float2(aspect * 0.5, 0.34);
    float2 p[4] = {
        centre + float2(-0.22 * aspect + 0.08 * sin(t * 2.1), -0.06 + 0.07 * cos(t * 1.7)),
        centre + float2( 0.20 * aspect + 0.07 * cos(t * 1.9), -0.02 + 0.08 * sin(t * 2.3)),
        centre + float2( 0.05 * sin(t * 1.3), 0.12 + 0.06 * cos(t * 2.7)),
        centre + float2(-0.05 * aspect + 0.10 * cos(t * 1.1), -0.16 + 0.05 * sin(t * 1.6)),
    };
    float baseR[4] = { 0.20, 0.18, 0.16, 0.13 };
    float swell = 1.0 + bass * 0.30 + 0.04 * sin(time * 0.9); // idle breathing + bass

    // Gaussian fields fall to true black between and around the blobs.
    float fields[4];
    float total = 0.0;
    for (int i = 0; i < 4; i++) {
        float2 d = w - p[i];
        float rad = baseR[i] * swell;
        float f = exp(-dot(d, d) / (rad * rad));
        fields[i] = f;
        total += f;
    }

    // OKLab weighted mix. Squared weights keep each blob's own hue instead of averaging.
    float w0 = fields[0] * fields[0], w1 = fields[1] * fields[1];
    float w2 = fields[2] * fields[2], w3 = fields[3] * fields[3];
    float3 lab = (u.lab0.xyz * w0 + u.lab1.xyz * w1 + u.lab2.xyz * w2 + u.lab3.xyz * w3)
               / max(w0 + w1 + w2 + w3, 1e-5);

    // Body: soft-edged core. Glow: halo that decays to black (no floor).
    float body = smoothstep(0.7, 1.8, total);
    float glow = smoothstep(0.2, 1.1, total) * (0.55 + 0.45 * u.intensity);
    float lum = clamp(body * 0.85 + glow * 0.3, 0.0, 1.0);
    // Elliptical mask around the cloud: corners and edges stay true black like the reference.
    float2 dm = (uv - centre) / float2(0.62 * aspect, 0.42);
    lum *= 1.0 - smoothstep(0.55, 1.0, length(dm));
    lum *= mix(0.8, 1.0, u.intensity);

    // Rich chroma, highlight only in the hot core (bass pumps it).
    lab.yz *= 1.25;
    lab.x = mix(lab.x, min(lab.x + 0.08, 0.92), body * (0.2 + bass * 0.4));
    float3 lin = max(oklabToLinear(lab), 0.0) * lum * lum; // squared: deeper falloff at edges

    // Fade to black toward the bottom so shelves sit on pure black.
    lin *= 1.0 - smoothstep(0.55, 0.95, position.y / size.y);
    lin *= u.dim;

    float3 rgb = linearToSrgb(lin);
    // Triangular-PDF dither, static per pixel, to break 8-bit banding in the dark falloff.
    // Only where there is light: on pure black the upscaled noise would show as a dot grid.
    float d1 = hash12(position * 1.37), d2 = hash12(position * 0.71 + 41.0);
    float lit = saturate(max(rgb.r, max(rgb.g, rgb.b)) * 24.0);
    rgb += (d1 + d2 - 1.0) / 255.0 * lit;

    return half4(half3(clamp(rgb, 0.0, 1.0)), 1.0h);
}
