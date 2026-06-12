#version 330 core
out vec4 FragColor;
in vec3 fragPos;

uniform float timeOfDay;
uniform float uSkyTime;
uniform sampler2D uSunTex;
uniform sampler2D uMoonTex;
uniform sampler2D uScrollTex;
uniform int uSkyMode;
uniform vec2 uScrollRepeat;
uniform float uScrollLookSensitivity;
uniform float uScrollVerticalInfluence;
uniform bool uHasScrollTexture;
uniform vec2 uViewportSize;
uniform vec2 uCameraAngles;
uniform mat4 projection;
uniform mat4 view;

const float PI = 3.14159265359;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

float noisePeriodic(vec2 p, vec2 period) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    vec2 i00 = mod(i + vec2(0.0, 0.0), period);
    vec2 i10 = mod(i + vec2(1.0, 0.0), period);
    vec2 i01 = mod(i + vec2(0.0, 1.0), period);
    vec2 i11 = mod(i + vec2(1.0, 1.0), period);
    return mix(
        mix(hash(i00), hash(i10), u.x),
        mix(hash(i01), hash(i11), u.x),
        u.y
    );
}

float fbm(vec2 p) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; ++i) {
        value += noise(p) * amp;
        p = p * 2.03 + vec2(17.2, 9.3);
        amp *= 0.5;
    }
    return value;
}

float fbmPeriodic(vec2 p, vec2 period) {
    float value = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; ++i) {
        value += noisePeriodic(p, period) * amp;
        p = p * 2.0 + vec2(17.2, 9.3);
        period *= 2.0;
        amp *= 0.5;
    }
    return value;
}

float starLayer(vec2 uv, float density, float threshold, float sharpness) {
    vec2 grid = uv * density;
    vec2 cell = floor(grid);
    cell.x = mod(cell.x, density);
    vec2 local = fract(grid) - 0.5;
    float seed = hash(cell);
    vec2 starOffset = vec2(hash(cell + 13.17), hash(cell + 71.43)) - 0.5;
    float distToStar = length(local - starOffset * 0.72);
    float starCore = smoothstep(0.045, 0.0, distToStar);
    float visible = step(threshold, seed);
    float brightness = pow(seed, sharpness);
    return starCore * visible * brightness;
}

vec3 reconstructSkyDir() {
    vec2 viewport = max(uViewportSize, vec2(1.0));
    vec2 ndc = (gl_FragCoord.xy / viewport) * 2.0 - 1.0;
    vec4 viewRay = inverse(projection) * vec4(ndc, 1.0, 1.0);
    float safeW = abs(viewRay.w) < 0.0001 ? 0.0001 : viewRay.w;
    vec3 viewDir = normalize(viewRay.xyz / safeW);
    return normalize(inverse(mat3(view)) * viewDir);
}

vec4 sampleBillboard(sampler2D tex, vec3 dir, vec3 centerDir, float angularRadius) {
    vec3 basisUp = abs(centerDir.y) > 0.96 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(basisUp, centerDir));
    vec3 up = normalize(cross(centerDir, right));

    float forward = dot(dir, centerDir);
    if (forward <= 0.0) {
        return vec4(0.0);
    }

    vec2 plane = vec2(dot(dir, right), dot(dir, up)) / max(forward, 0.001);
    vec2 uv = plane / tan(angularRadius) * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0);
    }

    return texture(tex, uv);
}

vec3 proceduralSky(vec3 dir, vec3 sunDir, float dayAmount) {
    float height = clamp(dir.y, -1.0, 1.0);
    float horizonMix = smoothstep(-0.18, 0.72, height);

    vec3 dayHorizon = vec3(0.84, 0.92, 1.02);
    vec3 dayUpper = vec3(0.18, 0.48, 0.88);
    vec3 twilightHorizon = vec3(1.02, 0.62, 0.34);
    vec3 twilightUpper = vec3(0.15, 0.22, 0.45);
    vec3 nightHorizon = vec3(0.03, 0.05, 0.10);
    vec3 nightUpper = vec3(0.005, 0.015, 0.045);

    float twilight = 1.0 - smoothstep(0.08, 0.38, abs(sunDir.y));
    vec3 horizonCol = mix(nightHorizon, twilightHorizon, twilight);
    horizonCol = mix(horizonCol, dayHorizon, dayAmount);
    vec3 upperCol = mix(nightUpper, twilightUpper, twilight);
    upperCol = mix(upperCol, dayUpper, dayAmount);

    vec3 skyColor = mix(horizonCol, upperCol, horizonMix);

    float sunDot = max(dot(dir, sunDir), 0.0);
    float mieGlow = pow(sunDot, 9.0);
    float aureole = pow(sunDot, 40.0);
    vec3 scatterColor = mix(vec3(1.05, 0.62, 0.30), vec3(1.0, 0.97, 0.92), dayAmount);
    skyColor += scatterColor * (mieGlow * 0.22 + aureole * 0.55) * mix(0.35, 1.0, dayAmount);

    float haze = exp(-max(height, -0.1) * 9.0);
    skyColor += mix(vec3(0.06, 0.08, 0.12), vec3(1.0, 0.93, 0.86), dayAmount) * haze * mix(0.05, 0.18, dayAmount);

    float cloudYaw = atan(dir.z, dir.x) / (2.0 * PI) + 0.5;
    float cloudBand = smoothstep(-0.12, 0.16, height) * (1.0 - smoothstep(0.68, 0.92, height));
    vec2 windA = vec2(uSkyTime * 0.012, uSkyTime * 0.004);
    vec2 windB = vec2(-uSkyTime * 0.006, uSkyTime * 0.009);
    vec2 cloudUv = vec2(cloudYaw * 6.0, height * 3.4 + 1.25);
    float broadClouds = fbmPeriodic(cloudUv + windA, vec2(6.0, 1024.0));
    float detailClouds = fbmPeriodic(cloudUv * 2.0 + windB, vec2(12.0, 2048.0));
    float cloudShape = broadClouds * 0.74 + detailClouds * 0.26;
    float cloudMask = smoothstep(0.50, 0.72, cloudShape) * cloudBand;
    float cloudSilver = pow(max(dot(dir, sunDir), 0.0), 5.0) * dayAmount;
    vec3 cloudShadow = mix(vec3(0.08, 0.10, 0.15), vec3(0.58, 0.65, 0.72), dayAmount);
    vec3 cloudBright = mix(vec3(0.20, 0.23, 0.30), vec3(1.0, 0.98, 0.93), dayAmount);
    vec3 cloudLit = mix(cloudShadow, cloudBright, 0.55 + cloudSilver * 0.45);
    float cloudAlpha = cloudMask * mix(0.08, 0.62, dayAmount);
    skyColor = mix(skyColor, cloudLit, cloudAlpha);
    skyColor += vec3(1.0, 0.92, 0.76) * cloudSilver * cloudMask * 0.12;

    float nightAmount = 1.0 - dayAmount;
    if (nightAmount > 0.001) {
        vec2 starUv = vec2(atan(dir.z, dir.x) / (2.0 * PI) + 0.5, asin(height) / PI + 0.5);
        float fineStars = starLayer(starUv, 190.0, 0.953, 2.9);
        float brightStars = starLayer(starUv + vec2(0.37, 0.19), 92.0, 0.974, 2.1);
        float twinkle = 0.82 + 0.18 * sin(uSkyTime * 1.7 + hash(floor(starUv * 145.0)) * 31.4);
        float starField = (fineStars * 0.78 + brightStars * 1.65) * twinkle;
        float starMask = smoothstep(-0.04, 0.28, height) * (1.0 - smoothstep(0.88, 1.0, height) * 0.25);
        vec3 galaxy = vec3(0.30, 0.38, 0.55) * pow(max(1.0 - abs(dot(dir, normalize(vec3(0.18, 0.88, -0.42)))), 0.0), 5.0);
        skyColor += (vec3(0.92, 0.94, 1.0) * starField * 1.8 + galaxy * 0.45) * nightAmount * starMask;
    }

    return skyColor;
}

vec3 scrollingSky(vec3 dir) {
    float yaw = atan(dir.z, dir.x) / (2.0 * PI) + 0.5;
    float vertical = asin(clamp(dir.y, -0.96, 0.96)) / PI + 0.5;
    float horizonLift = mix(0.0, uCameraAngles.y * 0.18, uScrollVerticalInfluence);
    float wind = uSkyTime * 0.018;
    vec2 uv = vec2((yaw + uCameraAngles.x * uScrollLookSensitivity * 0.35 + wind) * uScrollRepeat.x,
                   (vertical + horizonLift + sin(yaw * 6.28318 + uSkyTime * 0.22) * 0.012) * uScrollRepeat.y);
    vec3 cloudColor = texture(uScrollTex, uv).rgb;

    vec2 highUv = vec2(uv.x + uSkyTime * 0.006, (0.82 + horizonLift) * uScrollRepeat.y);
    vec3 zenithColor = texture(uScrollTex, highUv).rgb;
    float zenithFade = smoothstep(0.70, 0.92, dir.y);
    float nadirFade = smoothstep(-0.72, -0.92, dir.y);
    vec3 bottomColor = texture(uScrollTex, vec2(uv.x, (0.08 + horizonLift) * uScrollRepeat.y)).rgb;
    return mix(mix(cloudColor, zenithColor, zenithFade), bottomColor, nadirFade);
}

void main() {
    vec3 dir = reconstructSkyDir();

    float t = fract(timeOfDay);
    float angle = t * 2.0 * PI;
    vec3 sunDir = normalize(vec3(cos(angle), sin(angle) * 0.55, sin(angle)));
    vec3 moonDir = -sunDir;
    float dayAmount = smoothstep(-0.12, 0.16, sunDir.y);
    float nightAmount = 1.0 - dayAmount;

    if (uSkyMode == 1 && uHasScrollTexture) {
        FragColor = vec4(scrollingSky(dir), 1.0);
        return;
    }

    vec3 col = proceduralSky(dir, sunDir, dayAmount);

    float sunDot = max(dot(dir, sunDir), 0.0);
    float moonDot = max(dot(dir, moonDir), 0.0);

    vec4 sunSprite = sampleBillboard(uSunTex, dir, sunDir, 0.11);
    vec4 moonSprite = sampleBillboard(uMoonTex, dir, moonDir, 0.075);

    vec3 sunHalo = vec3(1.0, 0.97, 0.9) * (pow(sunDot, 18.0) * 0.45 + pow(sunDot, 220.0) * 4.0);
    vec3 moonHalo = vec3(0.75, 0.82, 1.0) * (pow(moonDot, 20.0) * 0.16);

    col += sunHalo * dayAmount;
    col = mix(col, moonHalo + col, nightAmount * 0.55);
    col = mix(col, col + sunSprite.rgb * (0.35 + sunSprite.a * 1.65), sunSprite.a * dayAmount);
    col = mix(col, col + moonSprite.rgb * (0.25 + moonSprite.a * 1.15), moonSprite.a * nightAmount);

    col = 1.0 - exp(-col * 1.15);
    FragColor = vec4(col, 1.0);
}
