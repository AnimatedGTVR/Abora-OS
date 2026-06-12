#version 330 core

layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aUv;

uniform vec2 u_viewportSize;
uniform vec2 u_boundsMin;
uniform vec2 u_boundsMax;

out vec2 vScreenPos;
out vec2 vUv;

void main() {
    vec2 screenPos = mix(u_boundsMin, u_boundsMax, aUv);
    vec2 ndc = vec2(
        (screenPos.x / max(u_viewportSize.x, 1.0)) * 2.0 - 1.0,
        1.0 - (screenPos.y / max(u_viewportSize.y, 1.0)) * 2.0
    );
    gl_Position = vec4(ndc, 0.0, 1.0);
    vScreenPos = screenPos;
    vUv = aUv;
}
