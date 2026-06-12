#version 330 core
out vec4 FragColor;

in vec2 TexCoord;

uniform sampler2D sceneTex;
uniform float threshold = 1.0;
uniform float softKnee = 0.25;

void main() {
    vec3 c = texture(sceneTex, TexCoord).rgb;
    float luma = dot(c, vec3(0.2125, 0.7154, 0.0721));
    float knee = max(threshold * softKnee, 1e-4);
    float soft = clamp(luma - threshold + knee, 0.0, 2.0 * knee);
    soft = (soft * soft) / max(4.0 * knee + 1e-4, 1e-4);
    float contribution = max(soft, luma - threshold);
    contribution /= max(luma, 1e-4);
    vec3 masked = c * clamp(contribution, 0.0, 1.0);
    FragColor = vec4(masked, 1.0);
}
