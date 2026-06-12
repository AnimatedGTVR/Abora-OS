#version 330 core

layout (location = 0) in vec3 aPosition;
layout (location = 1) in vec2 aUv;
layout (location = 2) in vec4 aColor;

out vec2 vUv;
out vec4 vColor;

uniform mat4 u_view;
uniform mat4 u_projection;
uniform vec3 u_cameraForward;

void main() {
    vUv = aUv;
    vColor = aColor;
    gl_Position = u_projection * u_view * vec4(aPosition, 1.0);
}
