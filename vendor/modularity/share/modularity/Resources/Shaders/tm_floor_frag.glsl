#version 330 core

in vec2 vUv;

out vec4 FragColor;

uniform mat4 u_inverseViewProjection;
uniform mat4 u_viewProjection;
uniform sampler2D u_floorTexture;
uniform vec3 u_cameraPosition;
uniform vec2 u_boundsMinXZ;
uniform vec2 u_boundsMaxXZ;
uniform vec2 u_uvScale;
uniform float u_floorHeight;
uniform float u_maxDistance;
uniform float u_perspectiveStrength;
uniform float u_horizonOffset;
uniform bool u_hasTexture;

vec3 sampleProceduralFloor(vec2 uv, vec2 worldXZ) {
    vec2 checkerCell = floor(uv);
    float checker = mod(checkerCell.x + checkerCell.y, 2.0);
    vec3 colorA = vec3(0.18, 0.22, 0.28);
    vec3 colorB = vec3(0.11, 0.14, 0.19);
    vec3 base = mix(colorA, colorB, checker);

    vec2 gridUv = abs(fract(uv) - 0.5);
    float gridLine = 1.0 - smoothstep(0.46, 0.50, max(gridUv.x, gridUv.y));
    base += vec3(0.06, 0.09, 0.12) * gridLine;

    float centerGlow = 1.0 - clamp(length(worldXZ) * 0.02, 0.0, 1.0);
    base += vec3(0.03, 0.04, 0.06) * centerGlow;
    return base;
}

void main() {
    vec2 ndc = vec2(vUv.x * 2.0 - 1.0, vUv.y * 2.0 - 1.0 + u_horizonOffset);

    vec4 nearPoint = u_inverseViewProjection * vec4(ndc, -1.0, 1.0);
    vec4 farPoint = u_inverseViewProjection * vec4(ndc, 1.0, 1.0);
    nearPoint /= max(nearPoint.w, 0.0001);
    farPoint /= max(farPoint.w, 0.0001);

    vec3 rayDir = normalize(farPoint.xyz - nearPoint.xyz);
    rayDir.y *= u_perspectiveStrength;
    rayDir = normalize(rayDir);

    if (abs(rayDir.y) < 0.0001) {
        discard;
    }

    float t = (u_floorHeight - u_cameraPosition.y) / rayDir.y;
    if (t <= 0.0) {
        discard;
    }

    vec3 worldPos = u_cameraPosition + rayDir * t;
    if (worldPos.x < u_boundsMinXZ.x || worldPos.x > u_boundsMaxXZ.x ||
        worldPos.z < u_boundsMinXZ.y || worldPos.z > u_boundsMaxXZ.y) {
        discard;
    }

    float distanceToCamera = distance(worldPos.xz, u_cameraPosition.xz);
    if (distanceToCamera > u_maxDistance) {
        discard;
    }

    vec2 uv = worldPos.xz * u_uvScale;
    vec4 shaded = u_hasTexture
        ? texture(u_floorTexture, uv)
        : vec4(sampleProceduralFloor(uv, worldPos.xz), 1.0);

    float fade = 1.0 - smoothstep(u_maxDistance * 0.72, u_maxDistance, distanceToCamera);
    shaded.rgb *= mix(0.55, 1.0, fade);

    vec4 clipPos = u_viewProjection * vec4(worldPos, 1.0);
    float ndcDepth = clipPos.z / max(clipPos.w, 0.0001);
    gl_FragDepth = ndcDepth * 0.5 + 0.5;

    FragColor = vec4(shaded.rgb, 1.0);
}
