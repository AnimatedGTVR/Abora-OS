#version 330 core
out vec4 FragColor;

in vec2 TexCoord;

uniform sampler2D maskTex;
uniform vec2 texelSize;
uniform vec3 outlineColor = vec3(1.0, 0.65, 0.18);
uniform float outlineRadiusPx = 2.7;
uniform float outlineSoftnessPx = 1.15;
uniform float outlineOpacity = 0.95;

float maskAt(vec2 uv)
{
    return step(0.5, texture(maskTex, uv).r);
}

void main()
{
    float center = maskAt(TexCoord);
    if (center > 0.5) {
        FragColor = vec4(0.0);
        return;
    }

    float searchRadius = max(1.0, outlineRadiusPx + outlineSoftnessPx);
    int r = int(ceil(searchRadius));

    float minDist = 1e9;
    for (int y = -8; y <= 8; ++y) {
        if (y < -r || y > r) continue;
        for (int x = -8; x <= 8; ++x) {
            if (x < -r || x > r) continue;
            vec2 d = vec2(float(x), float(y));
            float dist = length(d);
            if (dist > searchRadius) continue;
            if (maskAt(TexCoord + d * texelSize) > 0.5) {
                minDist = min(minDist, dist);
            }
        }
    }

    if (minDist > 1e8) {
        FragColor = vec4(0.0);
        return;
    }

    float inner = max(0.0, outlineRadiusPx - outlineSoftnessPx);
    float outer = outlineRadiusPx + outlineSoftnessPx;
    float alpha = 1.0 - smoothstep(inner, outer, minDist);
    alpha *= outlineOpacity;

    FragColor = vec4(outlineColor, alpha);
}
