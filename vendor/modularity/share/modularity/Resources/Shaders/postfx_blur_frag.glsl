#version 330 core
out vec4 FragColor;

in vec2 TexCoord;

uniform sampler2D image;
uniform vec2 texelSize;
uniform bool horizontal = true;
uniform float sigma = 3.0;
uniform int radius = 5;

const float PI = 3.14159265359;

void main() {
    float twoSigma2 = 2.0 * sigma * sigma;
    vec2 dir = horizontal ? vec2(1.0, 0.0) : vec2(0.0, 1.0);

    vec3 result = texture(image, TexCoord).rgb;
    float weightSum = 1.0;

    for (int i = 1; i <= radius; ++i) {
        float w = exp(-(float(i * i)) / twoSigma2);
        vec2 offset = dir * texelSize * float(i);
        result += texture(image, TexCoord + offset).rgb * w;
        result += texture(image, TexCoord - offset).rgb * w;
        weightSum += 2.0 * w;
    }

    result /= weightSum;
    FragColor = vec4(result, 1.0);
}
