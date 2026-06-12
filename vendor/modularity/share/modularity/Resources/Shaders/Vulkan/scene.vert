#version 450

layout(push_constant) uniform ScenePushConstants {
    mat4 mvp;
    vec4 color;
} uScene;

layout(location = 0) out vec4 outColor;

const vec3 kCubeVertices[36] = vec3[](
    vec3(-0.5, -0.5,  0.5), vec3( 0.5, -0.5,  0.5), vec3( 0.5,  0.5,  0.5),
    vec3(-0.5, -0.5,  0.5), vec3( 0.5,  0.5,  0.5), vec3(-0.5,  0.5,  0.5),

    vec3( 0.5, -0.5, -0.5), vec3(-0.5, -0.5, -0.5), vec3(-0.5,  0.5, -0.5),
    vec3( 0.5, -0.5, -0.5), vec3(-0.5,  0.5, -0.5), vec3( 0.5,  0.5, -0.5),

    vec3(-0.5, -0.5, -0.5), vec3(-0.5, -0.5,  0.5), vec3(-0.5,  0.5,  0.5),
    vec3(-0.5, -0.5, -0.5), vec3(-0.5,  0.5,  0.5), vec3(-0.5,  0.5, -0.5),

    vec3( 0.5, -0.5,  0.5), vec3( 0.5, -0.5, -0.5), vec3( 0.5,  0.5, -0.5),
    vec3( 0.5, -0.5,  0.5), vec3( 0.5,  0.5, -0.5), vec3( 0.5,  0.5,  0.5),

    vec3(-0.5,  0.5,  0.5), vec3( 0.5,  0.5,  0.5), vec3( 0.5,  0.5, -0.5),
    vec3(-0.5,  0.5,  0.5), vec3( 0.5,  0.5, -0.5), vec3(-0.5,  0.5, -0.5),

    vec3(-0.5, -0.5, -0.5), vec3( 0.5, -0.5, -0.5), vec3( 0.5, -0.5,  0.5),
    vec3(-0.5, -0.5, -0.5), vec3( 0.5, -0.5,  0.5), vec3(-0.5, -0.5,  0.5)
);

void main() {
    vec3 position = kCubeVertices[gl_VertexIndex % 36];
    gl_Position = uScene.mvp * vec4(position, 1.0);
    outColor = uScene.color;
}
