// WaveBlob.metal — audio-reactive "Моя волна" backdrop: liquid silk that moves with the track.
//
// Drawn by `WaveRenderer` into a CAMetalLayer drawable that is smaller than the view (Core
// Animation stretches it over the hero). Everything here is built from a handful of sines, so
// the picture is band-limited: it survives the upscale and costs next to nothing per pixel.
//
// Each pixel:
//   1. Is pulled by the finger and zoomed in a touch on every kick.
//   2. Has its coordinate folded by a few rounds of sine warping. The phases advance with
//      `flow`, a clock the CPU runs faster while the music is loud and shoves on each kick,
//      so the fluid moves with the track instead of merely getting brighter.
//   3. Reads its colour from the folded coordinate: the 4 palette colours mixed in OKLab
//      (the palette arrives already converted) with chroma kept through the blends.
//   4. Belongs to one of the overlapping sheets the folded plane is cut into: bright at the
//      sheet's crisp leading edge, sinking into the palette's darkest colour behind it;
//      highs make the edges glint. A kick sends a band of light up every sheet, from its
//      dark tail to the edge, where it breaks like surf.
//   5. Fades into true black around and below the cloud and gets a 1-LSB dither against banding.

#include <metal_stdlib>
using namespace metal;

// Must match `WaveUniforms` in WaveDynamics.swift (same order, same types).
struct WaveUniforms {
    float4 bands;      // bass, low-mid, high-mid, treble (0...1, smoothed on the CPU)
    float4 pulse;      // x = kick punch, y = high-end sparkle, z = energy (slow loudness), w = sway (slow bass)
    float4 rippleAge;  // seconds since each of the last kicks (large = none)
    float4 rippleAmp;  // how hard that kick was
    float4 lab0;       // palette in OKLab (xyz), w unused
    float4 lab1;
    float4 lab2;
    float4 lab3;
    float2 size;       // drawable size in pixels
    float2 touch;      // touch point in drawable pixels
    float time;        // seconds, already slowed when paused
    float flow;        // the fluid's own clock, driven by the music
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

// Interleaved gradient noise (Jimenez): evenly spread and high-frequency, so a dither made
// of it has no visible grain or grid.
static float ign(float2 p) {
    return fract(52.9829189 * fract(dot(p, float2(0.06711056, 0.00583715))));
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

// Blend of two OKLab colours that keeps its chroma: a straight blend of two vivid hues
// passes through grey.
static float3 mixLab(float3 a, float3 b, float t) {
    float3 c = mix(a, b, t);
    float want = mix(length(a.yz), length(b.yz), t);
    c.yz *= min(want / max(length(c.yz), 1e-3), 3.0);
    return c;
}

// MARK: - Fragment

fragment half4 waveFragment(WaveVertexOut in [[stage_in]], constant WaveUniforms &u [[buffer(0)]]) {
    float2 position = in.position.xy;
    float2 size = max(u.size, float2(1.0));
    float aspect = size.x / size.y;
    float yN = position.y / size.y;
    // Normalised coords: y in 0...1, x scaled by aspect so shapes stay round.
    float2 uv = position / size.y;
    float2 centre = float2(aspect * 0.5, 0.34);

    float treble = u.bands.w;
    float punch = u.pulse.x, sparkle = u.pulse.y, energy = u.pulse.z, sway = u.pulse.w;

    // Finger pull: pixels near the touch are displaced toward it (gaussian falloff).
    float2 toTouch = u.touch / size.y - uv;
    float pull = u.touchAmt * exp(-dot(toTouch, toTouch) * 9.0);
    uv += toTouch * pull * 0.45;

    float2 p = (uv - centre) * (1.0 - 0.02 * punch);

    // Sine folding. All clock factors are multiples of 0.001 (see WaveSmoother.period).
    float f = u.flow, t = u.time;
    // How hard it folds follows the slow values only: fast ones would make the shapes twitch.
    float swirl = 0.60 + 0.12 * sway + 0.10 * energy;
    // A tall, narrow view (the phone) would only show a couple of sheets: fold it finer.
    float fine = 2.3 * (1.0 + 0.7 * saturate((1.0 - aspect) * 2.0));
    float2 q = p * fine;
    for (int i = 1; i <= 5; i++) {
        float n = float(i);
        q.x += swirl / n * sin(n * 1.35 * q.y + f * (0.31 + 0.13 * n) + 1.7 * n);
        q.y += swirl / n * cos(n * 1.15 * q.x - f * (0.27 + 0.11 * n) + 2.3 * n + t * 0.05);
    }

    // Sheets: the folded plane is cut into overlapping layers. Each has a crisp leading edge
    // (anti-aliased over a pixel and a half) and falls off softly behind it.
    float phi = q.x * 0.66 + q.y * 0.44 + 0.25 * sin(q.y * 0.8 + t * 0.05);
    float aa = fwidth(phi) * 1.5 + 1e-4;
    float s = fract(phi);
    float sheet = floor(phi);
    float over = smoothstep(1.0 - aa, 1.0, s);
    float ramp = s * (1.0 - over);
    float rimLight = smoothstep(0.9 - aa, 1.0 - aa, s) * (1.0 - over);
    // Where the folding squeezes many sheets into a few pixels there is nothing to resolve:
    // let them melt into their average instead of aliasing.
    float resolved = 1.0 - smoothstep(0.18, 0.55, aa);
    ramp = mix(0.5, ramp, resolved);
    rimLight *= resolved;

    // Kicks: a band of light runs up every sheet from its dark tail and breaks on the leading
    // edge, like surf. The sheets answer a moment apart, so it rolls through the stack; the
    // band follows the sheets' own shapes and moves nothing.
    float surf = 0.0, breaking = 0.0;
    float delay = fract(sheet * 0.618) * 0.12;
    for (int i = 0; i < 4; i++) {
        float age = max(u.rippleAge[i] - delay, 0.0);
        float amp = u.rippleAmp[i] * exp(-age * 1.6);
        float front = age * 1.7;                    // in sheet widths
        float x = (s - front) / 0.16;
        surf += amp * exp(-x * x) * smoothstep(0.0, 0.25, front);
        float y = (front - 1.0) / 0.22;
        breaking += amp * exp(-y * y);
    }
    surf *= resolved * (1.0 - over);
    breaking = min(breaking, 1.5);

    // Colour: two slow coordinates across the folded plane pick between the four colours;
    // every sheet starts somewhere else in the palette.
    float a = 0.5 + 0.5 * sin(q.x * 1.3 + 0.6 * sin(q.y * 0.7 + t * 0.07) + sheet * 2.4);
    float b = 0.5 + 0.5 * sin(q.y * 1.2 + 1.9 + 0.6 * sin(q.x * 0.6 - t * 0.06) + sheet * 1.7);
    a = smoothstep(0.1, 0.9, a);
    b = smoothstep(0.1, 0.9, b);
    float3 lab = mixLab(mixLab(u.lab0.xyz, u.lab1.xyz, a), mixLab(u.lab2.xyz, u.lab3.xyz, a), b);

    // The palette's darkest colour: what the sheets' tails and the cloud's rim sink into
    // on their way to black (a light colour simply dimmed turns to mud).
    float3 deep = u.lab0.xyz;
    deep = u.lab1.x < deep.x ? u.lab1.xyz : deep;
    deep = u.lab2.x < deep.x ? u.lab2.xyz : deep;
    deep = u.lab3.x < deep.x ? u.lab3.xyz : deep;

    // Where the cloud is: a wide soft body whose outline follows the fluid, gone before the bottom.
    float2 pe = mix(p, q / fine, 0.35);
    float2 e = pe / float2(max(0.36 * aspect, 0.2), 0.27 + 0.04 * energy);
    float cloud = exp(-dot(e, e));
    cloud *= 1.0 - smoothstep(0.50, 0.93, yN);

    float body = saturate(pow(ramp, 1.3) + 0.55 * surf);
    lab = mixLab(deep, lab, mix(0.45, 1.0, body) * smoothstep(0.0, 0.45, cloud));
    float lum = cloud * mix(0.60, 1.0, body) * mix(0.62, 1.0, u.intensity) * (1.0 + 0.20 * punch + 0.08 * energy);
    float3 base = max(oklabToLinear(lab), 0.0);
    float3 lin = base * lum * lum;
    // Light catching the edges; highs make it glint.
    lin += rimLight * cloud * cloud * (0.10 + 0.30 * sparkle + 0.08 * treble + 0.40 * breaking) * mix(base, float3(1.0), 0.5);
    lin *= u.dim;

    float3 rgb = linearToSrgb(lin);
    // Triangular-PDF dither, static per pixel, to break 8-bit banding in the dark falloff.
    // Only where there is light: on pure black the upscaled noise would show as a dot grid.
    float d1 = ign(position), d2 = ign(position + float2(47.0, 17.0));
    float lit = saturate(max(rgb.r, max(rgb.g, rgb.b)) * 24.0);
    rgb += (d1 + d2 - 1.0) / 255.0 * lit;

    return half4(half3(clamp(rgb, 0.0, 1.0)), 1.0h);
}
