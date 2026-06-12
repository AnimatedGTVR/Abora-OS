#version 450

layout(set = 0, binding = 0) uniform sampler2D texture1;
layout(set = 0, binding = 1) uniform sampler2D overlayTex;
layout(set = 0, binding = 2) uniform sampler2D normalMap;

const int MAX_SCENE_LIGHTS = 16;
struct SceneLight {
    vec4 typeRangeAngles; // x=type, y=range, z=innerCos, w=outerCos
    vec4 position;
    vec4 direction;
    vec4 colorIntensity;
};

layout(set = 1, binding = 0) uniform SceneLightingBlock {
    vec4 cameraAndCount;      // xyz = camera, w = lightCount
    vec4 ambientAndStrength;  // xyz = ambient tint, w = global strength
    SceneLight lights[MAX_SCENE_LIGHTS];
} uSceneLighting;

layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec4 inColor;
layout(location = 0) out vec4 fragColor;

layout(push_constant) uniform ScenePushConstants {
    mat4 mvp;
    vec4 color;
    vec4 uvTransform;
    vec4 params;
    vec4 lighting;
    vec4 objectPos;
} uScene;

void main() {
    float mixAmount = clamp(uScene.params.x, 0.0, 1.0);
    bool hasOverlay = (uScene.params.z > 0.5);
    bool hasNormalMap = (uScene.lighting.w > 0.5);
    float speed = mix(0.08, 1.2, mixAmount);
    vec2 scrollDir = normalize(vec2(1.0, 0.3));
    vec2 transformedUv = inTexCoord * uScene.uvTransform.xy + uScene.uvTransform.zw;
    vec2 uv = transformedUv + scrollDir * (uScene.params.w * speed);
    vec4 texel = texture(texture1, uv);
    vec3 texColor = texel.rgb;
    if (hasOverlay) {
        vec2 overlayDir = normalize(vec2(-0.65, 1.0));
        vec2 overlayUv = transformedUv + overlayDir * (uScene.params.w * speed * 0.65);
        vec3 overlay = texture(overlayTex, overlayUv).rgb;
        texColor = mix(texColor, overlay, mixAmount);
    }
    vec3 baseColor = texColor * inColor.rgb;

    bool unlit = (uScene.params.y > 0.5);
    if (unlit) {
        fragColor = vec4(baseColor, texel.a * inColor.a);
        return;
    }

    vec3 N = normalize(inNormal);
    if (hasNormalMap) {
        vec3 mapN = texture(normalMap, uv).xyz * 2.0 - 1.0;
        mapN = normalize(vec3(mapN.xy * 0.75, max(0.05, mapN.z)));
        N = normalize(mix(N, mapN, 0.65));
    }
    vec3 fragPos = uScene.objectPos.xyz;
    vec3 viewDir = normalize(uSceneLighting.cameraAndCount.xyz - fragPos);
    float specularStrength = clamp(uScene.lighting.y, 0.0, 2.0);
    float shininess = max(uScene.lighting.z, 1.0);

    vec3 ambient = baseColor *
                   clamp(uScene.lighting.x, 0.0, 1.0) *
                   uSceneLighting.ambientAndStrength.xyz *
                   max(uSceneLighting.ambientAndStrength.w, 0.0);
    vec3 lit = ambient;

    int lightCount = int(clamp(uSceneLighting.cameraAndCount.w, 0.0, float(MAX_SCENE_LIGHTS)));
    if (lightCount == 0) {
        vec3 L = normalize(vec3(0.35, 0.9, 0.2));
        vec3 H = normalize(L + viewDir);
        float diff = max(dot(N, L), 0.0);
        float spec = pow(max(dot(N, H), 0.0), shininess) * specularStrength;
        lit += baseColor * diff + vec3(spec);
    } else {
        for (int i = 0; i < lightCount; ++i) {
            SceneLight light = uSceneLighting.lights[i];
            float type = light.typeRangeAngles.x;
            float range = max(light.typeRangeAngles.y, 0.001);
            float attenuation = 1.0;
            vec3 L;

            if (type < 0.5) {
                L = normalize(-light.direction.xyz);
            } else {
                vec3 toLight = light.position.xyz - fragPos;
                float dist = length(toLight);
                if (dist < 1e-4) continue;
                L = toLight / dist;
                float falloff = clamp(1.0 - (dist / range), 0.0, 1.0);
                attenuation = falloff * falloff;
            }

            if (type >= 1.5 && type < 2.5) {
                float innerCos = light.typeRangeAngles.z;
                float outerCos = light.typeRangeAngles.w;
                float spotCos = dot(-L, normalize(light.direction.xyz));
                attenuation *= smoothstep(outerCos, innerCos, spotCos);
            } else if (type >= 2.5) {
                attenuation *= max(dot(normalize(light.direction.xyz), -L), 0.0);
            }

            float diff = max(dot(N, L), 0.0);
            if (diff <= 0.0 || attenuation <= 0.0) continue;

            vec3 H = normalize(L + viewDir);
            float spec = pow(max(dot(N, H), 0.0), shininess) * specularStrength;
            vec3 lightColor = light.colorIntensity.rgb * max(light.colorIntensity.a, 0.0);
            lit += (baseColor * diff + vec3(spec)) * lightColor * attenuation;
        }
    }

    fragColor = vec4(lit, texel.a * inColor.a);
}
