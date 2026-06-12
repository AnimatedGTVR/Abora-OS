#version 330 core
layout (location = 0) in vec3 aPos;

uniform mat4 model;
uniform mat4 lightSpaceMatrix;

out vec3 WorldPos;

void main()
{
    vec4 world = model * vec4(aPos, 1.0);
    WorldPos = world.xyz;
    gl_Position = lightSpaceMatrix * world;
}
