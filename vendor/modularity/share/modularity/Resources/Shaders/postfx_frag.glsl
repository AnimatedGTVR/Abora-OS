#version 330 core
out vec4 FragColor;

in vec2 TexCoord;

uniform sampler2D sceneTex;
uniform sampler2D bloomTex;
uniform sampler2D historyTex;

uniform bool enableHDR = true;
uniform int toneMapper = 2;
uniform float whitePoint = 4.0;
uniform float gamma = 2.2;

uniform bool enableBloom = false;
uniform float bloomIntensity = 0.8;

uniform bool enableColorAdjust = false;
uniform float exposure = 0.0; // EV stops
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform vec3 colorFilter = vec3(1.0);

uniform bool enableMotionBlur = false;
uniform bool hasHistory = false;
uniform float motionBlurStrength = 0.15;
uniform float motionBlurThreshold = 0.04;
uniform float motionBlurClamp = 0.35;

uniform bool enableVignette = false;
uniform float vignetteIntensity = 0.35;
uniform float vignetteSmoothness = 0.25;

uniform bool enableChromatic = false;
uniform float chromaticAmount = 0.0025;

uniform bool enableSharpen = false;
uniform float sharpenStrength = 0.15;

uniform bool enableAO = false;
uniform float aoRadius = 0.0035;
uniform float aoStrength = 0.6;

uniform bool enableDither = false;
uniform float ditherIntensity = 0.65;
uniform int ditherColorBits = 5;
uniform float ditherDarkAdjustment = 0.35;
uniform float ditherPixelation = 0.0;
uniform float ditherSize = 1.0;
uniform float ditherContrast = 0.35;
uniform float ditherOffset = 0.0;
uniform int ditherPalette = 0;
uniform int ditherPattern = 4;
uniform bool enableStatic = false;
uniform float staticIntensity = 0.0;
uniform float staticGrainScale = 1.0;
uniform float staticDarkAreaInfluence = 0.0;
uniform float staticSpeed = 0.0;
uniform bool enableStaticDistortion = false;
uniform float staticDistortionHorizontalJitterAmount = 0.0;
uniform float staticDistortionLineDensity = 128.0;
uniform float staticDistortionGlitchFrequency = 0.0;
uniform float staticDistortionStrength = 0.0;
uniform bool enableLensDistortion = false;
uniform float lensDistortionAmount = 0.0;
uniform float lensDistortionEdgeFalloff = 0.75;
uniform vec2 lensDistortionCenterOffset = vec2(0.0);
uniform bool enableVHSOverlay = false;
uniform float vhsOverlayOpacity = 0.0;
uniform float vhsOverlayScanlineStrength = 0.0;
uniform float vhsOverlayTapeNoise = 0.0;
uniform float vhsOverlayChromaBleed = 0.0;
uniform float vhsOverlayBottomNoiseBandHeight = 0.0;
uniform float vhsOverlayBottomNoiseBandIntensity = 0.0;
uniform float vhsOverlayDistortionStrength = 0.0;
uniform float vhsOverlayAnimationSpeed = 0.0;
uniform float vhsOverlayColorBleed = 0.0;
uniform float vhsOverlayBanding = 0.0;
uniform bool enableWavyEffect = false;
uniform float wavyAmplitude = 0.0;
uniform float wavyFrequency = 16.0;
uniform float wavySpeed = 0.0;
uniform bool wavyVertical = false;

uniform vec2 texelSize = vec2(1.0 / 1280.0, 1.0 / 720.0);
uniform float u_time = 0.0;

float interleavedNoise(vec2 p);
vec3 toneMap(vec3 color);

vec3 applyColorAdjust(vec3 color) {
    if (enableColorAdjust) {
        color *= exp2(exposure);
        color = (color - 0.5) * contrast + 0.5;
        float luma = dot(color, vec3(0.299, 0.587, 0.114));
        color = mix(vec3(luma), color, saturation);
        color *= colorFilter;
    }
    return color;
}

vec3 sampleBase(vec2 uv) {
    return applyColorAdjust(texture(sceneTex, uv).rgb);
}

float luminance(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

float computeVignette(vec2 uv) {
    float dist = length(uv - vec2(0.5));
    float vig = smoothstep(0.8 - vignetteIntensity, 1.0 + vignetteSmoothness, dist);
    return clamp(1.0 - vig * vignetteIntensity, 0.0, 1.0);
}

vec3 applyChromatic(vec2 uv) {
    vec3 base = sampleBase(uv);
    vec2 dir = uv - vec2(0.5);
    float dist = max(length(dir), 0.0001);
    vec2 offset = normalize(dir) * chromaticAmount * (1.0 + dist * 2.0);
    vec3 rSample = sampleBase(uv + offset);
    vec3 bSample = sampleBase(uv - offset);
    vec3 ca = vec3(rSample.r, base.g, bSample.b);
    return mix(base, ca, 0.85);
}

vec2 applyLensDistortion(vec2 uv) {
    if (!enableLensDistortion || abs(lensDistortionAmount) <= 0.000001) {
        return uv;
    }

    vec2 center = vec2(0.5) + lensDistortionCenterOffset;
    vec2 delta = uv - center;
    float dist = length(delta);
    float falloff = smoothstep(clamp(lensDistortionEdgeFalloff, 0.0, 1.0), 1.0, dist * 1.41421356);
    float warp = lensDistortionAmount * falloff * falloff;
    return center + delta * (1.0 + warp);
}

vec2 applyWavyEffect(vec2 uv) {
    if (!enableWavyEffect || abs(wavyAmplitude) <= 0.000001) {
        return uv;
    }

    float phase = u_time * wavySpeed;
    float wave = sin((wavyVertical ? uv.x : uv.y) * wavyFrequency + phase);
    if (wavyVertical) {
        uv.y += wave * wavyAmplitude;
    } else {
        uv.x += wave * wavyAmplitude;
    }
    return uv;
}

vec2 applyStaticDistortion(vec2 uv) {
    if (!enableStaticDistortion || staticDistortionStrength <= 0.000001) {
        return uv;
    }

    float lineDensity = max(staticDistortionLineDensity, 1.0);
    float lineId = floor(uv.y * lineDensity);
    float timePhase = floor(u_time * staticDistortionGlitchFrequency);
    float lineNoise = interleavedNoise(vec2(lineId * 0.731, timePhase * 13.37 + lineId));
    float glitchMask = step(0.58, interleavedNoise(vec2(lineId + timePhase, lineId * 1.37 + 29.0)));
    float jitter = (lineNoise - 0.5) * staticDistortionHorizontalJitterAmount * staticDistortionStrength;
    uv.x += jitter * mix(0.35, 1.0, glitchMask);
    return uv;
}

vec3 applyStaticEffect(vec3 color) {
    if (!enableStatic || staticIntensity <= 0.000001) {
        return color;
    }

    float scale = max(staticGrainScale, 0.01);
    vec2 noiseUv = gl_FragCoord.xy / scale;
    float timeSeed = u_time * staticSpeed;
    float noiseR = interleavedNoise(noiseUv + vec2(timeSeed, timeSeed * 0.37));
    float noiseG = interleavedNoise(noiseUv + vec2(17.0, 53.0) + vec2(timeSeed * 1.11, timeSeed * 0.19));
    float noiseB = interleavedNoise(noiseUv + vec2(29.0, 11.0) - vec2(timeSeed * 0.93, timeSeed * 0.23));
    float luma = luminance(color);
    float darkFactor = mix(1.0, 1.0 + staticDarkAreaInfluence, 1.0 - luma);
    vec3 noise = vec3(noiseR, noiseG, noiseB) - 0.5;
    return clamp(color + noise * staticIntensity * darkFactor, 0.0, 1.0);
}

vec3 rgbToYiq(vec3 color) {
    return vec3(
        dot(color, vec3(0.299, 0.587, 0.114)),
        dot(color, vec3(0.596, -0.274, -0.322)),
        dot(color, vec3(0.211, -0.523, 0.312))
    );
}

vec3 yiqToRgb(vec3 yiq) {
    return vec3(
        yiq.x + 0.956 * yiq.y + 0.621 * yiq.z,
        yiq.x - 0.272 * yiq.y - 0.647 * yiq.z,
        yiq.x - 1.106 * yiq.y + 1.703 * yiq.z
    );
}

vec3 sampleDisplayBase(vec2 uv) {
    return toneMap(sampleBase(clamp(uv, vec2(0.0), vec2(1.0))));
}

vec2 applyVhsSignalWarp(vec2 uv, out float trackingMask, out float burstMask, out float headSwitchMask) {
    trackingMask = 0.0;
    burstMask = 0.0;
    headSwitchMask = 0.0;
    if (!enableVHSOverlay || vhsOverlayOpacity <= 0.000001) {
        return uv;
    }

    float speed = max(vhsOverlayAnimationSpeed, 0.0);
    float t = u_time * speed;
    float distortion = clamp(vhsOverlayDistortionStrength, 0.0, 2.0);
    float trackAmount = clamp(vhsOverlayBottomNoiseBandHeight, 0.0, 1.0);
    float burstAmount = clamp(vhsOverlayBottomNoiseBandIntensity, 0.0, 2.0);
    float line = floor(uv.y / max(texelSize.y, 1e-6));

    float jitterA = interleavedNoise(vec2(line * 0.071, floor(t * 22.0) + 13.0)) - 0.5;
    float jitterB = interleavedNoise(vec2(line * 0.193 + 7.0, floor(t * 12.0) + 3.0)) - 0.5;
    uv.x += (jitterA * 10.0 + jitterB * 6.0) * texelSize.x * distortion;
    uv.x += sin(uv.y * 170.0 + t * 11.0 + jitterB * 6.28318) * texelSize.x * 2.5 * distortion;

    float trackingSeed = floor(t * 1.7);
    float bandCenter = fract(interleavedNoise(vec2(trackingSeed, 0.37)) + t * 0.035);
    float bandWidth = mix(0.015, 0.16, trackAmount);
    trackingMask = (1.0 - smoothstep(bandWidth, bandWidth * 2.6, abs(uv.y - bandCenter))) * trackAmount;
    uv.x += trackingMask * (jitterB * 38.0 + sin(uv.y * 60.0 - t * 8.0) * 18.0) * texelSize.x * (0.35 + distortion);
    uv.y += trackingMask * sin(uv.y * 32.0 - t * 7.5 + jitterA * 4.0) * texelSize.y * 8.0 * distortion;

    headSwitchMask = (1.0 - smoothstep(0.0, 0.08 + trackAmount * 0.1, uv.y));
    uv.x += headSwitchMask * sin(uv.y * 980.0 + t * 30.0) * texelSize.x * (6.0 + burstAmount * 14.0);

    float burstGate = step(0.68, interleavedNoise(vec2(floor(t * 1.5) + 41.0, 7.3)));
    float burstCenter = fract(interleavedNoise(vec2(floor(t * 0.9) + 3.0, 17.0)) + t * 0.02);
    float burstBand = 1.0 - smoothstep(0.015, 0.09, abs(uv.y - burstCenter));
    burstMask = burstGate * burstBand * clamp(burstAmount * 0.6, 0.0, 1.0);
    uv.x += burstMask * (jitterA * 60.0 + 12.0) * texelSize.x * distortion;

    return clamp(uv, vec2(0.0), vec2(1.0));
}

vec3 applyVhsOverlay(vec3 color, vec2 uv) {
    if (!enableVHSOverlay || vhsOverlayOpacity <= 0.000001) {
        return color;
    }

    float trackingMask;
    float burstMask;
    float headSwitchMask;
    vec2 warpedUv = applyVhsSignalWarp(uv, trackingMask, burstMask, headSwitchMask);

    float chromaOffsetPx = mix(0.25, 6.0, clamp(vhsOverlayChromaBleed, 0.0, 1.0));
    float colorBleedPx = mix(0.0, 10.0, clamp(vhsOverlayColorBleed, 0.0, 1.0));
    vec2 dx = vec2(texelSize.x, 0.0);

    vec3 yiqM3 = rgbToYiq(sampleDisplayBase(warpedUv - dx * (chromaOffsetPx + colorBleedPx * 0.85)));
    vec3 yiqM2 = rgbToYiq(sampleDisplayBase(warpedUv - dx * (chromaOffsetPx * 0.65 + colorBleedPx * 0.35)));
    vec3 yiqM1 = rgbToYiq(sampleDisplayBase(warpedUv - dx * chromaOffsetPx));
    vec3 yiqC = rgbToYiq(sampleDisplayBase(warpedUv));
    vec3 yiqP1 = rgbToYiq(sampleDisplayBase(warpedUv + dx * chromaOffsetPx));
    vec3 yiqP2 = rgbToYiq(sampleDisplayBase(warpedUv + dx * (chromaOffsetPx * 0.65 + colorBleedPx * 0.35)));
    vec3 yiqP3 = rgbToYiq(sampleDisplayBase(warpedUv + dx * (chromaOffsetPx + colorBleedPx * 0.85)));

    vec3 signal;
    signal.x = dot(vec4(yiqM1.x, yiqC.x, yiqP1.x, yiqP2.x), vec4(0.12, 0.58, 0.2, 0.1));
    signal.x += (yiqM2.x + yiqP3.x) * 0.04;
    signal.y = dot(vec4(yiqM2.y, yiqM1.y, yiqC.y, yiqP1.y), vec4(0.18, 0.27, 0.32, 0.23));
    signal.y += (yiqP2.y + yiqM3.y) * 0.08;
    signal.z = dot(vec4(yiqM3.z, yiqM1.z, yiqP1.z, yiqP3.z), vec4(0.2, 0.28, 0.28, 0.2));
    signal.z += (yiqC.z + yiqP2.z + yiqM2.z) * 0.013;

    float crossColor = (yiqM1.x - yiqP1.x) * (0.03 + clamp(vhsOverlayColorBleed, 0.0, 1.0) * 0.08);
    signal.y += crossColor;
    signal.z -= crossColor * 0.65;
    signal.yz *= vec2(1.0 - clamp(vhsOverlayColorBleed, 0.0, 1.0) * 0.2,
                      1.0 - clamp(vhsOverlayColorBleed, 0.0, 1.0) * 0.3);

    vec3 ntscColor = clamp(yiqToRgb(signal), 0.0, 1.0);

    float speed = max(vhsOverlayAnimationSpeed, 0.0);
    float t = u_time * speed;
    float scanlinePhase = gl_FragCoord.y * 3.14159265 + t * 6.0;
    float scanline = 1.0 - clamp(vhsOverlayScanlineStrength, 0.0, 1.0) *
        (0.18 + 0.22 * (0.5 + 0.5 * sin(scanlinePhase)));
    ntscColor *= scanline;

    float noiseAmount = clamp(vhsOverlayTapeNoise, 0.0, 1.0);
    float grain0 = interleavedNoise(gl_FragCoord.xy * vec2(1.0, 0.85) + vec2(t * 31.0, t * 7.0)) - 0.5;
    float grain1 = interleavedNoise(gl_FragCoord.xy * vec2(0.75, 1.2) + vec2(19.0, t * 17.0)) - 0.5;
    float chromaNoise = interleavedNoise(gl_FragCoord.xy * vec2(0.5, 1.8) + vec2(t * 11.0, 53.0)) - 0.5;
    ntscColor += vec3(grain0, grain1, chromaNoise) * (0.08 + noiseAmount * 0.22);

    float banding = clamp(vhsOverlayBanding, 0.0, 1.0);
    if (banding > 0.0001) {
        float levels = mix(64.0, 10.0, banding);
        vec3 degraded = floor(clamp(ntscColor, 0.0, 1.0) * levels) / levels;
        ntscColor = mix(ntscColor, degraded, banding * 0.7);
    }

    float luma = luminance(ntscColor);
    ntscColor = mix(vec3(luma), ntscColor, 1.0 - clamp(vhsOverlayColorBleed, 0.0, 1.0) * 0.12);

    vec3 burstNoise = vec3(
        interleavedNoise(gl_FragCoord.xy * 1.8 + vec2(t * 53.0, 11.0)),
        interleavedNoise(gl_FragCoord.xy * 2.1 + vec2(17.0, t * 47.0)),
        interleavedNoise(gl_FragCoord.xy * 1.4 + vec2(t * 39.0, 29.0))) - 0.5;
    ntscColor += burstNoise * burstMask * 0.65;

    float headNoise = interleavedNoise(vec2(gl_FragCoord.x * 0.9, gl_FragCoord.y * 8.0 + t * 90.0)) - 0.5;
    ntscColor += vec3(headNoise) * headSwitchMask * clamp(vhsOverlayBottomNoiseBandIntensity, 0.0, 2.0) * 0.35;

    ntscColor = mix(ntscColor, ntscColor * 0.75 + vec3(0.07), trackingMask * 0.35);
    ntscColor = clamp(ntscColor, 0.0, 1.0);
    return mix(color, ntscColor, clamp(vhsOverlayOpacity, 0.0, 1.0));
}

float computeAOFactor(vec2 uv) {
    vec3 centerColor = sampleBase(uv);
    float centerLum = luminance(centerColor);
    float occlusion = 0.0;
    vec2 directions[4] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
    for (int i = 0; i < 4; ++i) {
        vec2 sampleUv = uv + directions[i] * aoRadius;
        vec3 sampleColor = sampleBase(sampleUv);
        float sampleLum = luminance(sampleColor);
        occlusion += max(0.0, centerLum - sampleLum);
    }
    occlusion /= 4.0;
    return clamp(1.0 - occlusion * aoStrength, 0.0, 1.0);
}

vec3 applySharpening(vec2 uv, vec3 color) {
    if (!enableSharpen) {
        return color;
    }

    vec3 north = sampleBase(uv + vec2(0.0, texelSize.y));
    vec3 south = sampleBase(uv - vec2(0.0, texelSize.y));
    vec3 east = sampleBase(uv + vec2(texelSize.x, 0.0));
    vec3 west = sampleBase(uv - vec2(texelSize.x, 0.0));
    vec3 blurred = (north + south + east + west) * 0.25;
    vec3 sharpened = color + (color - blurred) * sharpenStrength;
    return max(sharpened, vec3(0.0));
}

vec2 resolvePixelatedUv(vec2 uv) {
    if (ditherPixelation <= 1.0) {
        return uv;
    }
    vec2 stepSize = max(texelSize * ditherPixelation, texelSize);
    return clamp((floor(uv / stepSize) + vec2(0.5)) * stepSize, vec2(0.0), vec2(1.0));
}

float orderedDither4x4(vec2 fragCoord) {
    ivec2 cell = ivec2(mod(floor(fragCoord), 4.0));
    int index = cell.x + cell.y * 4;
    if (index == 0) return 0.0 / 16.0;
    if (index == 1) return 8.0 / 16.0;
    if (index == 2) return 2.0 / 16.0;
    if (index == 3) return 10.0 / 16.0;
    if (index == 4) return 12.0 / 16.0;
    if (index == 5) return 4.0 / 16.0;
    if (index == 6) return 14.0 / 16.0;
    if (index == 7) return 6.0 / 16.0;
    if (index == 8) return 3.0 / 16.0;
    if (index == 9) return 11.0 / 16.0;
    if (index == 10) return 1.0 / 16.0;
    if (index == 11) return 9.0 / 16.0;
    if (index == 12) return 15.0 / 16.0;
    if (index == 13) return 7.0 / 16.0;
    if (index == 14) return 13.0 / 16.0;
    return 5.0 / 16.0;
}

float orderedDither8x8(vec2 fragCoord) {
    const float bayer[64] = float[](
         0.0, 48.0, 12.0, 60.0,  3.0, 51.0, 15.0, 63.0,
        32.0, 16.0, 44.0, 28.0, 35.0, 19.0, 47.0, 31.0,
         8.0, 56.0,  4.0, 52.0, 11.0, 59.0,  7.0, 55.0,
        40.0, 24.0, 36.0, 20.0, 43.0, 27.0, 39.0, 23.0,
         2.0, 50.0, 14.0, 62.0,  1.0, 49.0, 13.0, 61.0,
        34.0, 18.0, 46.0, 30.0, 33.0, 17.0, 45.0, 29.0,
        10.0, 58.0,  6.0, 54.0,  9.0, 57.0,  5.0, 53.0,
        42.0, 26.0, 38.0, 22.0, 41.0, 25.0, 37.0, 21.0
    );
    ivec2 cell = ivec2(mod(floor(fragCoord), 8.0));
    return bayer[cell.x + cell.y * 8] / 64.0;
}

float orderedDither16x16(vec2 fragCoord) {
    vec2 coarse = floor(fragCoord * 0.5);
    float a = orderedDither8x8(coarse);
    float b = orderedDither8x8(coarse + vec2(11.0, 3.0));
    return clamp(mix(a, b, 0.5), 0.0, 1.0);
}

float checkerDither(vec2 fragCoord) {
    vec2 cell = mod(floor(fragCoord), 2.0);
    return (cell.x == cell.y) ? 0.2 : 0.8;
}

float interleavedNoise(vec2 p) {
    return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y));
}

float sampleDitherPattern(vec2 fragCoord) {
    float size = max(ditherSize, 1.0);
    vec2 scaled = fragCoord / size;
    if (ditherPattern == 0) {
        return orderedDither4x4(scaled);
    }
    if (ditherPattern == 1) {
        return orderedDither8x8(scaled);
    }
    if (ditherPattern == 2) {
        return orderedDither16x16(scaled);
    }
    if (ditherPattern == 3) {
        return checkerDither(scaled);
    }

    float bayer = orderedDither8x8(scaled);
    float coarse = orderedDither4x4(scaled * 0.5 + vec2(1.0, 2.0));
    float noise = interleavedNoise(floor(scaled) + vec2(17.0, 29.0));
    return clamp(mix(mix(bayer, coarse, 0.35), noise, 0.12), 0.0, 1.0);
}

float shapeDither(float threshold) {
    float centered = threshold - 0.5 + ditherOffset * 0.5;
    float gain = max(0.05, 1.0 + ditherContrast * 2.0);
    centered = sign(centered) * pow(abs(centered) * 2.0, gain) * 0.5;
    return clamp(centered + 0.5, 0.0, 1.0);
}

vec3 applyPalette(vec3 color) {
    if (ditherPalette == 0) {
        return color;
    }

    const vec3 warmA = vec3(0.090, 0.086, 0.145);
    const vec3 warmB = vec3(0.337, 0.302, 0.455);
    const vec3 warmC = vec3(0.729, 0.678, 0.745);
    const vec3 warmD = vec3(0.956, 0.934, 0.902);

    const vec3 coolA = vec3(0.074, 0.094, 0.176);
    const vec3 coolB = vec3(0.286, 0.322, 0.525);
    const vec3 coolC = vec3(0.690, 0.714, 0.835);
    const vec3 coolD = vec3(0.953, 0.960, 0.976);

    const vec3 monoA = vec3(0.08);
    const vec3 monoB = vec3(0.34);
    const vec3 monoC = vec3(0.67);
    const vec3 monoD = vec3(0.94);

    const vec3 sepiaA = vec3(0.110, 0.082, 0.055);
    const vec3 sepiaB = vec3(0.372, 0.258, 0.145);
    const vec3 sepiaC = vec3(0.702, 0.584, 0.384);
    const vec3 sepiaD = vec3(0.949, 0.902, 0.769);

    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 c0 = warmA;
    vec3 c1 = warmB;
    vec3 c2 = warmC;
    vec3 c3 = warmD;
    if (ditherPalette == 2) {
        c0 = coolA; c1 = coolB; c2 = coolC; c3 = coolD;
    } else if (ditherPalette == 3) {
        c0 = monoA; c1 = monoB; c2 = monoC; c3 = monoD;
    } else if (ditherPalette == 4) {
        c0 = sepiaA; c1 = sepiaB; c2 = sepiaC; c3 = sepiaD;
    }

    if (luma < 0.333) {
        return mix(c0, c1, smoothstep(0.0, 0.333, luma));
    }
    if (luma < 0.666) {
        return mix(c1, c2, smoothstep(0.333, 0.666, luma));
    }
    return mix(c2, c3, smoothstep(0.666, 1.0, luma));
}

vec3 toneMap(vec3 color) {
    vec3 mapped = max(color, vec3(0.0));
    if (enableHDR) {
        float wp = max(whitePoint, 0.001);
        vec3 scaled = mapped / wp;
        if (toneMapper == 1) {
            mapped = scaled / (vec3(1.0) + scaled);
        } else if (toneMapper == 2) {
            vec3 x = scaled;
            mapped = clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
        } else {
            mapped = clamp(scaled, 0.0, 1.0);
        }
    } else {
        mapped = clamp(mapped, 0.0, 1.0);
    }

    float safeGamma = max(gamma, 0.001);
    return pow(clamp(mapped, 0.0, 1.0), vec3(1.0 / safeGamma));
}

void main() {
    vec2 sampleUv = resolvePixelatedUv(TexCoord);
    sampleUv = applyLensDistortion(sampleUv);
    sampleUv = applyWavyEffect(sampleUv);
    sampleUv = applyStaticDistortion(sampleUv);
    vec3 color = sampleBase(sampleUv);

    if (enableChromatic) {
        color = applyChromatic(sampleUv);
    }

    if (enableAO) {
        color *= computeAOFactor(sampleUv);
    }

    if (enableVignette) {
        color *= computeVignette(sampleUv);
    }

    if (enableMotionBlur && hasHistory) {
        vec3 history = texture(historyTex, sampleUv).rgb;
        vec3 delta = clamp(history - color, vec3(-motionBlurClamp), vec3(motionBlurClamp));
        float diff = max(max(abs(delta.r), abs(delta.g)), abs(delta.b));
        float response = smoothstep(motionBlurThreshold,
                                    max(motionBlurThreshold * 4.0, motionBlurThreshold + 0.0001),
                                    diff);
        float mixAmt = clamp(motionBlurStrength * response, 0.0, 0.92);
        color += delta * mixAmt;
    }

    if (enableBloom) {
        vec3 glow = texture(bloomTex, TexCoord).rgb * bloomIntensity;
        color += glow;
    }

    color = applySharpening(sampleUv, color);
    vec3 outputColor = toneMap(color);
    outputColor = applyStaticEffect(outputColor);
    outputColor = applyVhsOverlay(outputColor, sampleUv);

    if (enableDither) {
        float levels = max(1.0, exp2(float(clamp(ditherColorBits, 1, 8))) - 1.0);
        float ditherBase = shapeDither(sampleDitherPattern(gl_FragCoord.xy));
        vec3 ditherNoise = vec3(
            ditherBase,
            shapeDither(sampleDitherPattern(gl_FragCoord.xy + vec2(1.0, 2.0))),
            shapeDither(sampleDitherPattern(gl_FragCoord.xy + vec2(2.0, 1.0)))) - 0.5;
        float luma = dot(outputColor, vec3(0.299, 0.587, 0.114));
        float darkBias = clamp((1.0 - luma) * max(ditherDarkAdjustment, 0.0), 0.0, 1.0);
        float strength = max(ditherIntensity, 0.0) * (0.65 + darkBias * 0.85);
        vec3 quantized = floor(clamp(outputColor, 0.0, 1.0) * levels + 0.5 + ditherNoise * strength) / levels;
        outputColor = clamp(applyPalette(clamp(quantized, 0.0, 1.0)), 0.0, 1.0);
    }

    FragColor = vec4(outputColor, 1.0);
}
