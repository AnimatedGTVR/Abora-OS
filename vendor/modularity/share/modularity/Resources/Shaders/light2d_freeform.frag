#version 330 core

in vec2 vScreenPos;

out vec4 FragColor;

uniform sampler2D u_cookieTex;
uniform bool u_useCookie;
uniform int u_blendMode;
uniform vec4 u_lightColor;
uniform float u_intensity;
uniform vec2 u_lightPos;
uniform float u_freeformFeather;
uniform float u_freeformEdgeFalloff;
uniform vec2 u_boundsMin;
uniform vec2 u_boundsMax;
uniform vec2 u_cookieScale;
uniform float u_cookieRotation;
uniform int u_polygonPointCount;
uniform vec2 u_polygonPoints[64];
uniform float u_radius;
uniform float u_innerRadius;
uniform float u_outerRadius;
uniform float u_falloffStrength;

float safeSignedDivisor(float value) {
    if (abs(value) >= 0.0001) {
        return value;
    }
    return (value < 0.0) ? -0.0001 : 0.0001;
}

float segmentDistance(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = dot(p - a, ab) / max(dot(ab, ab), 0.0001);
    t = clamp(t, 0.0, 1.0);
    return length(p - mix(a, b, t));
}

vec2 rotate2D(vec2 value, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(value.x * c - value.y * s, value.x * s + value.y * c);
}

float cookieValue(vec2 worldPos) {
    if (!u_useCookie) {
        return 1.0;
    }
    vec2 size = max(u_boundsMax - u_boundsMin, vec2(0.001));
    vec2 uv = (worldPos - u_boundsMin) / size;
    uv = uv * 2.0 - 1.0;
    uv = rotate2D(uv, -u_cookieRotation);
    uv /= max(u_cookieScale, vec2(0.001));
    uv = uv * 0.5 + 0.5;
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return 0.0;
    }
    return texture(u_cookieTex, uv).a;
}

void main() {
    if (u_polygonPointCount < 3) {
        discard;
    }

    bool inside = false;
    float minDistance = 1e20;
    for (int i = 0, j = u_polygonPointCount - 1; i < u_polygonPointCount; j = i++) {
        vec2 a = u_polygonPoints[i];
        vec2 b = u_polygonPoints[j];
        float edgeDeltaY = b.y - a.y;
        bool intersect = ((a.y > vScreenPos.y) != (b.y > vScreenPos.y)) &&
            (vScreenPos.x < (b.x - a.x) * (vScreenPos.y - a.y) / safeSignedDivisor(edgeDeltaY) + a.x);
        if (intersect) {
            inside = !inside;
        }
        minDistance = min(minDistance, segmentDistance(vScreenPos, a, b));
    }

    float feather = max(0.0, u_freeformFeather);
    float insideAttenuation = inside ? 1.0 : 0.0;
    if (inside && feather > 0.0) {
        insideAttenuation = smoothstep(0.0, feather, minDistance);
        insideAttenuation = pow(clamp(insideAttenuation, 0.0, 1.0), max(0.01, u_freeformEdgeFalloff));
    }

    float outerRadius = max(u_outerRadius, max(u_radius, 0.001));
    float innerRadius = clamp(u_innerRadius, 0.0, outerRadius);
    float outsideAttenuation = 0.0;
    if (!inside) {
        float outsideDistance = max(0.0, minDistance - feather);
        outsideAttenuation = 1.0 - smoothstep(innerRadius, outerRadius, outsideDistance);
        outsideAttenuation = pow(clamp(outsideAttenuation, 0.0, 1.0), max(0.01, 1.0 + u_falloffStrength * 2.5));
    }

    float attenuation = max(insideAttenuation, outsideAttenuation);
    attenuation *= cookieValue(vScreenPos);
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
