#version 450

layout(push_constant) uniform SkyboxPushConstants {
    mat4 viewProj;
    vec4 params;
    vec4 scroll;
    vec4 camera;
} uSky;

layout(location = 0) out vec3 outDir;

void main() {
    vec2 pos;
    if (gl_VertexIndex == 0) {
        pos = vec2(-1.0, -1.0);
    } else if (gl_VertexIndex == 1) {
        pos = vec2(3.0, -1.0);
    } else {
        pos = vec2(-1.0, 3.0);
    }
    outDir = vec3(pos, 1.0);
    gl_Position = vec4(pos, 1.0, 1.0);
}
