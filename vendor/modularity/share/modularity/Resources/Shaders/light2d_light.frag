#version 330 core

in vec2 vScreenPos;
in vec2 vUv;

out vec4 FragColor;

uniform sampler2D u_cookieTex;
uniform bool u_useCookie;
uniform bool u_shadowEnabled;
uniform int u_lightType;
uniform int u_blendMode;
uniform vec4 u_lightColor;
uniform float u_intensity;
uniform float u_radius;
uniform float u_innerRadius;
uniform float u_outerRadius;
uniform float u_falloffStrength;
uniform vec2 u_spotAngleCos;
uniform float u_rotation;
uniform vec2 u_lightPos;
uniform vec2 u_boundsMin;
uniform vec2 u_boundsMax;
uniform vec2 u_cookieScale;
uniform float u_cookieRotation;

vec2 rotate2D(vec2 value, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(value.x * c - value.y * s, value.x * s + value.y * c);
}

float computeCookie(vec2 localPos, float outerRadius) {
    if (!u_useCookie) {
        return 1.0;
    }
    float safeRadius = max(outerRadius, 0.001);
    vec2 uv = localPos / safeRadius;
    uv = rotate2D(uv, -u_cookieRotation);
    uv /= max(u_cookieScale, vec2(0.001));
    uv = uv * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return 0.0;
    }
    return texture(u_cookieTex, uv).a;
}

void main() {
    vec2 local = rotate2D(vScreenPos - u_lightPos, -u_rotation);
    float attenuation = 0.0;

    if (u_lightType == 4) {
        attenuation = 1.0;
    } else {
        float outerRadius = max(u_outerRadius, max(u_radius, 0.001));
        float innerRadius = clamp(u_innerRadius, 0.0, outerRadius);
        float distSq = dot(local, local);
        if (distSq >= outerRadius * outerRadius) {
            discard;
        }
        float dist = sqrt(max(distSq, 0.0));
        float edge = 1.0 - smoothstep(innerRadius, outerRadius, dist);
        attenuation = pow(clamp(edge, 0.0, 1.0), max(0.01, 1.0 + u_falloffStrength * 2.5));

        if (u_lightType == 1) {
            float invDist = inversesqrt(max(distSq, 0.0001));
            float coneDot = local.x * invDist;
            float spot = smoothstep(u_spotAngleCos.y, u_spotAngleCos.x, coneDot);
            attenuation *= clamp(spot, 0.0, 1.0);
        }
    }

    attenuation *= computeCookie(local, max(u_outerRadius, u_radius));
    if (u_shadowEnabled) {
        attenuation *= 1.0;
    }
    if (attenuation <= 0.0001) {
        discard;
    }

    vec3 rgb = u_lightColor.rgb * u_intensity * attenuation;
    float alpha = clamp(u_lightColor.a * attenuation, 0.0, 1.0);
    if (u_blendMode == 1) {
        rgb = mix(vec3(1.0), clamp(rgb, 0.0, 4.0), alpha);
        alpha = 1.0;
    }

    FragColor = vec4(rgb, alpha);
}
