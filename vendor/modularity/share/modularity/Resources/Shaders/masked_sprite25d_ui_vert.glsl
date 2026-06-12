#version 330 core

layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTexCoord;

uniform vec2 centerNdc;
uniform vec2 halfSizeNdc;
uniform float depthNdc;
uniform float rotationRadians;
uniform vec4 uvRect;

out vec2 TexCoord;

void main()
{
    vec2 local = vec2(aPos.x * halfSizeNdc.x, aPos.y * halfSizeNdc.y);
    float c = cos(rotationRadians);
    float s = sin(rotationRadians);
    vec2 rotated = vec2(local.x * c - local.y * s, local.x * s + local.y * c);

    gl_Position = vec4(centerNdc + rotated, depthNdc, 1.0);
    TexCoord = uvRect.xy + aTexCoord * uvRect.zw;
}
