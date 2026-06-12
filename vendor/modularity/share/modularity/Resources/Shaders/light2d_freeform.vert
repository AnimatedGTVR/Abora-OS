#version 330 core

layout (location = 0) in vec2 aPos;

uniform vec2 u_viewportSize;

out vec2 vScreenPos;

void main() {
    vec2 ndc = vec2(
        (aPos.x / max(u_viewportSize.x, 1.0)) * 2.0 - 1.0,
        1.0 - (aPos.y / max(u_viewportSize.y, 1.0)) * 2.0
    );
    gl_Position = vec4(ndc, 0.0, 1.0);
    vScreenPos = aPos;
}
