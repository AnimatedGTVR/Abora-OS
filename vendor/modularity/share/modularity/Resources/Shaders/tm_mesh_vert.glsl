#version 330 core

layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aTexCoord;

out vec3 vWorldPos;
out vec3 vNormal;
smooth out vec2 vUv;
noperspective out vec2 vAffineUv;

uniform mat4 u_model;
uniform mat4 u_view;
uniform mat4 u_projection;
uniform float u_time;
uniform bool u_wobbleEnabled;
uniform float u_wobbleStrength;
uniform float u_wobbleSpeed;
uniform float u_wobbleSeed;
uniform vec3 u_wobbleOffset;
uniform float u_presentationPitchDegrees;
uniform float u_pitchStretchStrength;
uniform float u_pitchCompressStrength;
uniform float u_pitchShearStrength;
uniform bool u_presentationSnapEnabled;
uniform float u_presentationSnapStep;
uniform bool u_cameraRelativeSnapEnabled;
uniform float u_cameraRelativeSnapStep;
uniform bool u_vertexSnapEnabled;
uniform float u_vertexSnapStep;
uniform bool u_screenSnapEnabled;
uniform float u_screenSnapStep;
uniform vec2 u_viewportSize;

vec3 snapVec3(vec3 value, float stepSize) {
    float safeStep = max(stepSize, 0.0001);
    return floor((value / safeStep) + 0.5) * safeStep;
}

vec2 snapVec2(vec2 value, float stepSize) {
    float safeStep = max(stepSize, 0.0001);
    return floor((value / safeStep) + 0.5) * safeStep;
}

void main() {
    vec3 presentedPos = aPos;
    if (u_vertexSnapEnabled && u_vertexSnapStep > 0.0) {
        presentedPos = snapVec3(presentedPos, u_vertexSnapStep);
    }

    if (u_wobbleEnabled && u_wobbleStrength > 0.0) {
        float phase = dot(aPos + (u_wobbleOffset * 0.125), vec3(0.73, 1.17, 1.53)) + u_wobbleSeed;
        float wobbleTime = u_time * u_wobbleSpeed;
        vec3 wobble = vec3(
            sin(phase + wobbleTime * 0.93),
            sin((phase * 1.31) + wobbleTime * 1.11),
            cos((phase * 0.77) + wobbleTime * 0.79)
        );
        presentedPos += wobble * vec3(u_wobbleStrength * 0.45,
                                      u_wobbleStrength * 0.65,
                                      u_wobbleStrength * 0.45);
    }

    vec4 worldPos = u_model * vec4(presentedPos, 1.0);
    if (u_presentationSnapEnabled && u_presentationSnapStep > 0.0) {
        worldPos.xyz = snapVec3(worldPos.xyz, u_presentationSnapStep);
    }

    vec4 viewPos = u_view * worldPos;
    if (u_cameraRelativeSnapEnabled && u_cameraRelativeSnapStep > 0.0) {
        viewPos.xyz = snapVec3(viewPos.xyz, u_cameraRelativeSnapStep);
    }

    float pitchNormalized = clamp(u_presentationPitchDegrees / 65.0, -1.0, 1.0);
    float pitchUp = max(pitchNormalized, 0.0);
    float pitchDown = max(-pitchNormalized, 0.0);
    float depthWeight = clamp((-viewPos.z) / 24.0, 0.0, 1.0);
    float verticalScale = 1.0 + (pitchUp * max(u_pitchStretchStrength, 0.0)) -
                          (pitchDown * max(u_pitchCompressStrength, 0.0));
    float shearAmount = pitchNormalized * max(u_pitchShearStrength, 0.0) * (0.45 + depthWeight * 0.55);
    viewPos.y *= verticalScale;
    viewPos.y += viewPos.x * shearAmount;

    vec4 presentedWorldPos = inverse(u_view) * viewPos;
    vWorldPos = presentedWorldPos.xyz;
    vNormal = mat3(transpose(inverse(u_model))) * aNormal;
    vUv = aTexCoord;
    vAffineUv = aTexCoord;

    vec4 clipPos = u_projection * viewPos;
    if (u_screenSnapEnabled && u_screenSnapStep > 0.0) {
        vec2 safeViewport = max(u_viewportSize, vec2(1.0));
        vec2 ndc = clipPos.xy / max(abs(clipPos.w), 0.0001);
        vec2 pixelPos = (ndc * 0.5 + 0.5) * safeViewport;
        pixelPos = snapVec2(pixelPos, u_screenSnapStep);
        ndc = ((pixelPos / safeViewport) * 2.0) - 1.0;
        clipPos.xy = ndc * clipPos.w;
    }

    gl_Position = clipPos;
}
