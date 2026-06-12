#version 330 core

in vec2 vUv;
in vec4 vColor;

out vec4 FragColor;

uniform sampler2D u_spriteTexture;
uniform bool u_hasTexture;

void main() {
    vec4 texel = u_hasTexture ? texture(u_spriteTexture, vUv) : vec4(1.0);
    vec4 color = texel * vColor;
    if (color.a < 0.05) {
        discard;
    }
    FragColor = color;
}
