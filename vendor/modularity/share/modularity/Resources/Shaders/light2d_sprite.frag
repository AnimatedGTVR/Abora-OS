#version 330 core

in vec2 vUv;
in vec4 vColor;
in vec4 vParams;

out vec4 FragColor;

uniform sampler2D u_spriteTex;
uniform sampler2D u_additiveLightTex;
uniform sampler2D u_multiplyLightTex;
uniform sampler2D u_subtractiveLightTex;
uniform vec2 u_viewportSize;
uniform vec3 u_baseAmbient;
uniform bool u_hasAdditiveLight;
uniform bool u_hasMultiplyLight;
uniform bool u_hasSubtractiveLight;

void main() {
    vec4 sprite = texture(u_spriteTex, vUv) * vColor;
    if (sprite.a <= 0.0001) {
        discard;
    }

    float receiveLighting = vParams.x;
    float unlit = vParams.y;
    float emissive = max(0.0, vParams.z);

    vec3 result = sprite.rgb;
    if (receiveLighting > 0.5 && unlit < 0.5) {
        result = sprite.rgb * u_baseAmbient;
        if (u_hasAdditiveLight || u_hasMultiplyLight || u_hasSubtractiveLight) {
            vec2 lightUv = gl_FragCoord.xy / max(u_viewportSize, vec2(1.0));
            vec3 additive = u_hasAdditiveLight ? texture(u_additiveLightTex, lightUv).rgb : vec3(0.0);
            vec3 multiply = u_hasMultiplyLight ? texture(u_multiplyLightTex, lightUv).rgb : vec3(1.0);
            vec3 subtractive = u_hasSubtractiveLight ? texture(u_subtractiveLightTex, lightUv).rgb : vec3(0.0);
            result = (result + sprite.rgb * additive) * multiply;
            result = max(vec3(0.0), result - sprite.rgb * subtractive);
        }
    }

    result += sprite.rgb * emissive;
    FragColor = vec4(result, sprite.a);
}
