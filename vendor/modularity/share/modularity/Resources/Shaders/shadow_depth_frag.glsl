#version 330 core

in vec3 WorldPos;

uniform vec3 lightPos;
uniform float farPlane;

void main()
{
    float dist = length(WorldPos - lightPos);
    gl_FragDepth = clamp(dist / max(farPlane, 0.001), 0.0, 1.0);
}
