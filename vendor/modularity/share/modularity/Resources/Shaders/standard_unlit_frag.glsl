#version 330 core
out vec4 FragColor;

in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoord;

uniform sampler2D texture1;
uniform sampler2D overlayTex;
uniform float mixAmount = 0.2;
uniform bool hasOverlay = false;
uniform vec4 uvTransform = vec4(1.0, 1.0, 0.0, 0.0);

uniform vec3 materialColor = vec3(1.0);
uniform float materialAlpha = 1.0;

void main()
{
    vec2 uv = TexCoord * uvTransform.xy + uvTransform.zw;
    vec4 tex1 = texture(texture1, uv);
    vec3 texColor = tex1.rgb;
    if (hasOverlay) {
        vec3 overlay = texture(overlayTex, uv).rgb;
        texColor = mix(texColor, overlay, mixAmount);
    }

    vec3 baseColor = texColor * materialColor;
    float alpha = tex1.a * materialAlpha;
    if (alpha <= 0.001) {
        discard;
    }

    FragColor = vec4(baseColor, alpha);
}
