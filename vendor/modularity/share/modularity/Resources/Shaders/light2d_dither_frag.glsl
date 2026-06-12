#version 330 core

in vec2 TexCoord;

out vec4 FragColor;

uniform sampler2D sceneTex;
uniform vec2 u_viewportSize;
uniform float u_ditherIntensity;
uniform int u_colorBits;
uniform float u_darkAdjustment;
uniform float u_ditherScale;
uniform float u_pixelation;
uniform float u_exposure;
uniform float u_contrast;
uniform float u_saturation;
uniform vec3 u_colorFilter;
uniform float u_vignetteIntensity;
uniform float u_vignetteSmoothness;
uniform float u_chromaticAmount;
uniform float u_sharpenStrength;
uniform float u_grainAmount;
uniform float u_scanlineIntensity;
uniform float u_time;

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
    float scale = max(u_ditherScale, 1.0);
    ivec2 cell = ivec2(mod(floor(fragCoord / scale), 8.0));
    return bayer[cell.x + cell.y * 8] / 64.0;
}

float interleavedGradientNoise(vec2 fragCoord) {
    return fract(52.9829189 * fract(0.06711056 * fragCoord.x + 0.00583715 * fragCoord.y));
}

vec2 resolveSampleCoord(vec2 fragCoord) {
    float pixelation = max(u_pixelation, 1.0);
    if (pixelation <= 1.0) {
        return fragCoord;
    }
    return (floor(fragCoord / pixelation) + vec2(0.5)) * pixelation;
}

vec3 sampleScene(vec2 uv, vec2 texel, float chromaticAmount) {
    vec2 clampedUv = clamp(uv, vec2(0.0), vec2(1.0));
    if (chromaticAmount <= 0.000001) {
        return texture(sceneTex, clampedUv).rgb;
    }

    vec2 centerDir = clampedUv - vec2(0.5);
    vec2 offset = centerDir * chromaticAmount * 24.0 + texel * chromaticAmount * 128.0;
    float r = texture(sceneTex, clamp(clampedUv + offset, vec2(0.0), vec2(1.0))).r;
    float g = texture(sceneTex, clampedUv).g;
    float b = texture(sceneTex, clamp(clampedUv - offset, vec2(0.0), vec2(1.0))).b;
    return vec3(r, g, b);
}

vec3 applyColorAdjustments(vec3 color) {
    color *= exp2(u_exposure);
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(luma), color, max(u_saturation, 0.0));
    color = ((color - 0.5) * max(u_contrast, 0.0)) + 0.5;
    color *= u_colorFilter;
    return clamp(color, 0.0, 1.0);
}

void main() {
    vec2 viewport = max(u_viewportSize, vec2(1.0));
    vec2 texel = 1.0 / viewport;
    vec2 sampleCoord = resolveSampleCoord(gl_FragCoord.xy);
    vec2 uv = clamp(sampleCoord / viewport, vec2(0.0), vec2(1.0));

    vec4 source = texture(sceneTex, uv);
    vec3 color = sampleScene(uv, texel, u_chromaticAmount);

    if (u_sharpenStrength > 0.0001) {
        vec3 north = texture(sceneTex, clamp(uv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rgb;
        vec3 south = texture(sceneTex, clamp(uv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rgb;
        vec3 east = texture(sceneTex, clamp(uv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 west = texture(sceneTex, clamp(uv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rgb;
        vec3 blur = (north + south + east + west) * 0.25;
        color = mix(color, color + (color - blur), clamp(u_sharpenStrength, 0.0, 2.0));
    }

    color = applyColorAdjustments(color);

    if (u_grainAmount > 0.0001) {
        float grain = interleavedGradientNoise(gl_FragCoord.xy + vec2(u_time * 37.0, u_time * 19.0)) - 0.5;
        color = clamp(color + grain * u_grainAmount, 0.0, 1.0);
    }

    float levels = max(1.0, exp2(float(clamp(u_colorBits, 1, 8))) - 1.0);

    float ditherBase = mix(
        orderedDither8x8(gl_FragCoord.xy),
        interleavedGradientNoise(gl_FragCoord.xy + vec2(u_time * 11.0, u_time * 7.0)),
        0.22
    );
    float ditherR = ditherBase;
    float ditherG = mix(orderedDither8x8(gl_FragCoord.xy + vec2(1.0, 3.0)),
                        interleavedGradientNoise(gl_FragCoord.xy + vec2(17.0, 53.0)),
                        0.22);
    float ditherB = mix(orderedDither8x8(gl_FragCoord.xy + vec2(3.0, 1.0)),
                        interleavedGradientNoise(gl_FragCoord.xy + vec2(29.0, 11.0)),
                        0.22);

    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    float darkBias = clamp((1.0 - luma) * max(u_darkAdjustment, 0.0), 0.0, 1.0);
    float strength = max(u_ditherIntensity, 0.0) * (1.0 + darkBias);

    vec3 noise = vec3(ditherR, ditherG, ditherB) - 0.5;
    vec3 quantized = floor(clamp(color, 0.0, 1.0) * levels + 0.5 + noise * strength) / levels;
    color = clamp(quantized, 0.0, 1.0);

    if (u_scanlineIntensity > 0.0001) {
        float scanline = 0.75 + 0.25 * cos(sampleCoord.y * 3.14159265);
        color *= mix(1.0, scanline, clamp(u_scanlineIntensity, 0.0, 1.0));
    }

    if (u_vignetteIntensity > 0.0001) {
        vec2 centered = uv * 2.0 - 1.0;
        float dist = length(centered);
        float radius = 1.35 - u_vignetteIntensity * 0.85;
        float softness = max(u_vignetteSmoothness, 0.05);
        float vignette = 1.0 - smoothstep(radius - softness, radius, dist);
        color *= mix(1.0, vignette, u_vignetteIntensity);
    }

    FragColor = vec4(clamp(color, 0.0, 1.0), source.a);
}
