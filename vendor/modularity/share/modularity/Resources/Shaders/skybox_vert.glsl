#version 330 core
layout (location = 0) in vec3 aPos;

out vec3 fragPos;

uniform mat4 projection;
uniform mat4 view;

void main()
{
    vec2 pos;
    if (gl_VertexID == 0) {
        pos = vec2(-1.0, -1.0);
    } else if (gl_VertexID == 1) {
        pos = vec2(3.0, -1.0);
    } else {
        pos = vec2(-1.0, 3.0);
    }
    fragPos = vec3(pos, 1.0);
    gl_Position = vec4(pos, 1.0, 1.0);
}
