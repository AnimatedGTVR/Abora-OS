#version 330 core

in vec2 TexCoord;

uniform sampler2D spriteTexture;
uniform vec4 tint;

out vec4 FragColor;

void main()
{
    vec4 color = texture(spriteTexture, TexCoord) * tint;
    if (color.a <= 0.01) {
        discard;
    }
    FragColor = color;
}
