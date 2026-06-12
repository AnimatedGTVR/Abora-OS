#version 330 core
out vec4 FragColor;

in vec3 FragPos;
in vec3 Normal;
in vec2 TexCoord;

uniform sampler2D texture1;
uniform sampler2D overlayTex;
uniform sampler2D normalMap;
uniform samplerCube reflectionCube;
uniform float mixAmount = 0.2;
uniform bool hasOverlay = false;
uniform bool hasNormalMap = false;
uniform bool hasReflectionCast = false;
uniform bool unlit = false;
uniform float reflectionIntensity = 0.0;
uniform float reflectionFadeStart = 4.0;
uniform float reflectionFadeEnd = 24.0;
uniform vec4 uvTransform = vec4(1.0, 1.0, 0.0, 0.0);

uniform vec3 viewPos;
uniform vec3 materialColor = vec3(1.0);
uniform float materialAlpha = 1.0;

uniform float ambientStrength = 0.2;
uniform vec3 ambientColor = vec3(1.0);
uniform float specularStrength = 0.5;
uniform float shininess = 32.0;
uniform float normalMapIntensity = 1.0;

uniform bool fogEnabled = false;
uniform int fogMode = 0;
uniform vec3 fogColor = vec3(0.65, 0.72, 0.78);
uniform float fogStart = 20.0;
uniform float fogEnd = 120.0;
uniform float fogDensity = 0.015;
uniform float fogHeight = 0.0;
uniform float fogHeightFalloff = 0.0;

const int MAX_LIGHTS = 32;
const int MAX_SHADOW_MAPS = 4;
uniform int lightCount = 0; // up to MAX_LIGHTS

// type: 0 dir, 1 point, 2 spot, 3 area (rect)
uniform int lightTypeArr[MAX_LIGHTS];
uniform vec3 lightDirArr[MAX_LIGHTS];
uniform vec3 lightPosArr[MAX_LIGHTS];
uniform vec3 lightColorArr[MAX_LIGHTS];
uniform float lightIntensityArr[MAX_LIGHTS];
uniform float lightRangeArr[MAX_LIGHTS];
uniform float lightInnerCosArr[MAX_LIGHTS];
uniform float lightOuterCosArr[MAX_LIGHTS];
uniform vec2 lightAreaSizeArr[MAX_LIGHTS];
uniform float lightAreaFadeArr[MAX_LIGHTS];
uniform int lightShadowMapArr[MAX_LIGHTS];
uniform int lightShadowKindArr[MAX_LIGHTS]; // 0 off, 1 cube, 2 directional
uniform int lightShadowModeArr[MAX_LIGHTS]; // 0 off, 1 hard, 2 soft
uniform float lightShadowBiasArr[MAX_LIGHTS];
uniform float lightShadowSoftnessArr[MAX_LIGHTS];
uniform float lightShadowFarArr[MAX_LIGHTS];
uniform mat4 lightShadowMatrixArr[MAX_LIGHTS];

uniform samplerCube shadowCube0;
uniform samplerCube shadowCube1;
uniform samplerCube shadowCube2;
uniform samplerCube shadowCube3;
uniform sampler2D dirShadow0;
uniform sampler2D dirShadow1;
uniform sampler2D dirShadow2;
uniform sampler2D dirShadow3;

float sampleShadowCube(int mapIndex, vec3 sampleDir)
{
    if (mapIndex == 0) return texture(shadowCube0, sampleDir).r;
    if (mapIndex == 1) return texture(shadowCube1, sampleDir).r;
    if (mapIndex == 2) return texture(shadowCube2, sampleDir).r;
    if (mapIndex == 3) return texture(shadowCube3, sampleDir).r;
    return 1.0;
}

float sampleDirectionalShadow(int mapIndex, vec2 uv)
{
    if (mapIndex == 0) return texture(dirShadow0, uv).r;
    if (mapIndex == 1) return texture(dirShadow1, uv).r;
    if (mapIndex == 2) return texture(dirShadow2, uv).r;
    if (mapIndex == 3) return texture(dirShadow3, uv).r;
    return 1.0;
}

vec2 getDirectionalShadowTexelSize(int mapIndex)
{
    if (mapIndex == 0) return 1.0 / vec2(textureSize(dirShadow0, 0));
    if (mapIndex == 1) return 1.0 / vec2(textureSize(dirShadow1, 0));
    if (mapIndex == 2) return 1.0 / vec2(textureSize(dirShadow2, 0));
    if (mapIndex == 3) return 1.0 / vec2(textureSize(dirShadow3, 0));
    return vec2(0.0);
}

float computeShadowOcclusion(int lightIndex, vec3 lightToFrag, float nl, vec3 worldPos)
{
    int mode = lightShadowModeArr[lightIndex];
    int mapIndex = lightShadowMapArr[lightIndex];
    int shadowKind = lightShadowKindArr[lightIndex];
    if (mode <= 0 || mapIndex < 0 || mapIndex >= MAX_SHADOW_MAPS || shadowKind <= 0) return 0.0;

    float baseBias = max(lightShadowBiasArr[lightIndex], 0.0001);
    float slopeBias = baseBias * (1.0 - clamp(nl, 0.0, 1.0));
    float bias = max(baseBias * 0.25, slopeBias);

    if (shadowKind == 2) {
        vec4 lightSpace = lightShadowMatrixArr[lightIndex] * vec4(worldPos, 1.0);
        vec3 projCoords = lightSpace.xyz / max(lightSpace.w, 0.0001);
        projCoords = projCoords * 0.5 + 0.5;
        if (projCoords.z <= 0.0 || projCoords.z >= 1.0) return 0.0;
        if (projCoords.x <= 0.0 || projCoords.x >= 1.0 || projCoords.y <= 0.0 || projCoords.y >= 1.0) return 0.0;

        float closestDepth = sampleDirectionalShadow(mapIndex, projCoords.xy);
        if (mode == 1) {
            return (projCoords.z - bias > closestDepth) ? 1.0 : 0.0;
        }

        float softness = max(lightShadowSoftnessArr[lightIndex], 0.0);
        vec2 texelSize = getDirectionalShadowTexelSize(mapIndex);
        if (softness <= 0.0001 || texelSize.x <= 0.0 || texelSize.y <= 0.0) {
            return (projCoords.z - bias > closestDepth) ? 1.0 : 0.0;
        }

        float radius = max(1.0, softness * 80.0);
        float shadow = 0.0;
        float sampleCount = 0.0;
        for (int x = -1; x <= 1; ++x) {
            for (int y = -1; y <= 1; ++y) {
                vec2 offset = vec2(x, y) * texelSize * radius;
                float sampleDepth = sampleDirectionalShadow(mapIndex, projCoords.xy + offset);
                shadow += (projCoords.z - bias > sampleDepth) ? 1.0 : 0.0;
                sampleCount += 1.0;
            }
        }
        return shadow / max(sampleCount, 1.0);
    }

    float farPlane = max(lightShadowFarArr[lightIndex], 0.001);
    float currentDepth = length(lightToFrag);
    if (currentDepth <= 0.0001) return 0.0;
    float hardDepth = sampleShadowCube(mapIndex, lightToFrag) * farPlane;
    if (mode == 1) {
        return (currentDepth - bias > hardDepth) ? 1.0 : 0.0;
    }

    float softness = max(lightShadowSoftnessArr[lightIndex], 0.0);
    if (softness <= 0.0001) {
        return (currentDepth - bias > hardDepth) ? 1.0 : 0.0;
    }

    const vec3 sampleOffsetDirections[20] = vec3[](
        vec3(1, 1, 1), vec3(1, -1, 1), vec3(-1, -1, 1), vec3(-1, 1, 1),
        vec3(1, 1, -1), vec3(1, -1, -1), vec3(-1, -1, -1), vec3(-1, 1, -1),
        vec3(1, 1, 0), vec3(1, -1, 0), vec3(-1, -1, 0), vec3(-1, 1, 0),
        vec3(1, 0, 1), vec3(-1, 0, 1), vec3(1, 0, -1), vec3(-1, 0, -1),
        vec3(0, 1, 1), vec3(0, -1, 1), vec3(0, -1, -1), vec3(0, 1, -1)
    );

    float diskRadius = softness * (1.0 + currentDepth / farPlane);
    float shadow = 0.0;
    for (int i = 0; i < 20; ++i) {
        float closestDepth = sampleShadowCube(mapIndex, lightToFrag + sampleOffsetDirections[i] * diskRadius) * farPlane;
        shadow += (currentDepth - bias > closestDepth) ? 1.0 : 0.0;
    }
    return shadow / 20.0;
}

const float PI = 3.14159265359;

vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - clamp(cosTheta, 0.0, 1.0), 5.0);
}

float distributionGGX(float NdotH, float roughness)
{
    float a = max(roughness * roughness, 0.02);
    float a2 = a * a;
    float d = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, 0.0001);
}

float geometrySchlickGGX(float NdotX, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotX / max(NdotX * (1.0 - k) + k, 0.0001);
}

float geometrySmith(float NdotV, float NdotL, float roughness)
{
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

vec3 evaluateDirectSpecular(
    vec3 N, vec3 V, vec3 L, vec3 F0,
    float roughness, float smoothness,
    float specPower, float specEnergy,
    vec3 lightColor, float intensity)
{
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    if (NdotL <= 0.0 || NdotV <= 0.0) {
        return vec3(0.0);
    }

    vec3 H = normalize(V + L);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);

    float D = distributionGGX(NdotH, roughness);
    float G = geometrySmith(NdotV, NdotL, roughness);
    vec3 F = fresnelSchlick(VdotH, F0);
    vec3 microfacet = (D * G * F) / max(4.0 * NdotV * NdotL, 0.0001);

    // Extra direct reflection lobe so high smoothness pops clearly under direct lights.
    float refl = pow(max(dot(reflect(-L, N), V), 0.0), specPower * 1.25);
    float blinn = pow(max(NdotH, 0.0), specPower);
    vec3 enhanced = F * (0.8 * refl + 0.25 * blinn) * specEnergy;

    // Keep very rough surfaces close to matte, while preserving high-smoothness highlights.
    float smoothVisibility = mix(0.03, 1.0, smoothness * smoothness);

    return (microfacet * smoothVisibility + enhanced) * lightColor * intensity * NdotL;
}

float computeFogFactor()
{
    if (!fogEnabled) {
        return 0.0;
    }

    float dist = length(viewPos - FragPos);
    float factor = 0.0;
    if (fogMode == 1) {
        factor = 1.0 - exp(-max(fogDensity, 0.0) * dist);
    } else if (fogMode == 2) {
        float densityDistance = max(fogDensity, 0.0) * dist;
        factor = 1.0 - exp(-(densityDistance * densityDistance));
    } else {
        factor = smoothstep(fogStart, max(fogStart + 0.01, fogEnd), dist);
    }

    if (fogHeightFalloff > 0.0001) {
        float heightWeight = 1.0 - exp(-abs(FragPos.y - fogHeight) * fogHeightFalloff);
        factor *= clamp(heightWeight, 0.0, 1.0);
    }

    return clamp(factor, 0.0, 1.0);
}

vec3 applyFog(vec3 color)
{
    return mix(color, fogColor, computeFogFactor());
}

void main()
{
    vec2 uv = TexCoord * uvTransform.xy + uvTransform.zw;
    vec3 norm = normalize(Normal);
    vec3 viewDir = normalize(viewPos - FragPos);

    // Texture mixing (corrected)
    vec4 tex1 = texture(texture1, uv);
    vec3 texColor = tex1.rgb;
    if (hasOverlay) {
        vec4 overlay = texture(overlayTex, uv);
        texColor = mix(texColor, overlay.rgb, overlay.a * mixAmount);
    }
    vec3 baseColor = texColor * materialColor;
    float alpha = tex1.a * materialAlpha;
    if (alpha <= 0.001) {
        discard;
    }

    if (unlit) {
        FragColor = vec4(applyFog(baseColor), alpha);
        return;
    }

    // Normal map (tangent-space)
    if (hasNormalMap) {
        vec3 mapN = texture(normalMap, uv).xyz * 2.0 - 1.0;
        mapN.xy *= max(normalMapIntensity, 0.0);
        mapN = normalize(mapN);
        vec3 dp1 = dFdx(FragPos);
        vec3 dp2 = dFdy(FragPos);
        vec2 duv1 = dFdx(uv);
        vec2 duv2 = dFdy(uv);
        vec3 tangent = normalize(dp1 * duv2.y - dp2 * duv1.y);
        vec3 bitangent = normalize(-dp1 * duv2.x + dp2 * duv1.x);
        mat3 TBN = mat3(tangent, bitangent, normalize(Normal));
        norm = normalize(TBN * mapN);
    }

    vec3 albedo = pow(max(baseColor, vec3(0.0)), vec3(2.2));
    float metallic = clamp(specularStrength, 0.0, 1.0);
    float smoothness = clamp(shininess / 256.0, 0.0, 1.0);
    float roughness = clamp(1.0 - smoothness, 0.03, 1.0);
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 diffuseColor = albedo * (1.0 - metallic);

    vec3 ambient = ambientStrength * ambientColor * diffuseColor;
    vec3 lighting = ambient;

    int count = min(lightCount, MAX_LIGHTS);
    for (int i = 0; i < count; ++i) {
        int ltype = lightTypeArr[i];
        float intensity = lightIntensityArr[i];
        if (intensity <= 0.0) continue;

        vec3 lDirN = vec3(0.0, 1.0, 0.0);
        float attenuation = 1.0;
        bool isArea = false;
        vec3 areaNormal = vec3(0.0, 1.0, 0.0);
        vec3 areaTangent = vec3(1.0, 0.0, 0.0);
        vec3 areaBitangent = vec3(0.0, 0.0, 1.0);
        vec3 areaCenter = vec3(0.0);
        vec2 areaHalfSize = vec2(0.5);

        if (ltype == 0) {
            lDirN = -normalize(lightDirArr[i]);
        } else if (ltype == 3) { // area light approximate
            isArea = true;
            areaNormal = normalize(lightDirArr[i]);
            vec3 up = abs(areaNormal.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
            areaTangent = normalize(cross(up, areaNormal));
            areaBitangent = cross(areaNormal, areaTangent);

            areaCenter = lightPosArr[i];
            vec3 rel = FragPos - areaCenter;
            float distPlane = dot(rel, areaNormal);
            vec3 onPlane = FragPos - distPlane * areaNormal;
            areaHalfSize = lightAreaSizeArr[i] * 0.5;
            vec2 local;
            local.x = dot(onPlane - areaCenter, areaTangent);
            local.y = dot(onPlane - areaCenter, areaBitangent);

            float fade = clamp(lightAreaFadeArr[i], 0.0, 1.0);
            vec2 absLocal = abs(local);
            float edgeWeight = 1.0;
            if (fade < 0.0001) {
                if (absLocal.x > areaHalfSize.x || absLocal.y > areaHalfSize.y) continue;
            } else {
                vec2 inner = areaHalfSize * (1.0 - fade);
                vec2 delta = max(areaHalfSize - inner, vec2(0.0001));
                vec2 outside = max(absLocal - inner, vec2(0.0));
                float maxOutside = max(outside.x / delta.x, outside.y / delta.y);
                edgeWeight = 1.0 - clamp(maxOutside, 0.0, 1.0);
                if (edgeWeight <= 0.0) continue;
                edgeWeight = smoothstep(0.0, 1.0, edgeWeight);
            }

            vec3 closest = areaCenter + areaTangent * local.x + areaBitangent * local.y;

            vec3 lvec = closest - FragPos;
            float dist = length(lvec);
            if (dist < 1e-4) continue;
            lDirN = normalize(lvec);

            float range = lightRangeArr[i];
            if (range > 0.0 && dist > range) continue;
            if (range > 0.0) {
                float falloff = clamp(1.0 - (dist / range), 0.0, 1.0);
                attenuation = falloff * falloff;
            }
            float facing = max(dot(areaNormal, -lDirN), 0.0);
            attenuation *= facing * edgeWeight;
        } else {
            vec3 ldir = lightPosArr[i] - FragPos;
            float dist = length(ldir);
            lDirN = normalize(ldir);

            float range = lightRangeArr[i];
            if (range > 0.0 && dist > range) continue;
            if (range > 0.0) {
                float falloff = clamp(1.0 - (dist / range), 0.0, 1.0);
                attenuation = falloff * falloff;
            }
        }

        if (ltype == 2) {
            float cosTheta = dot(-lDirN, normalize(lightDirArr[i]));
            float spotAtten = smoothstep(lightOuterCosArr[i], lightInnerCosArr[i], cosTheta);
            attenuation *= spotAtten;
        }

        float nl = max(dot(norm, lDirN), 0.0);
        vec3 diffuse = nl * diffuseColor * lightColorArr[i] * intensity;

        // Dynamic scaling: smooth materials pop more, rough ones stay broad/matte.
        float specPower = mix(2.0, 4096.0, pow(smoothness, 1.35));
        float specEnergy = mix(0.0, 2.8, pow(smoothness, 0.7));
        vec3 specular;
        if (isArea) {
            vec3 sampleOffsets[9] = vec3[](
                vec3(0.0),
                areaTangent * areaHalfSize.x,
                -areaTangent * areaHalfSize.x,
                areaBitangent * areaHalfSize.y,
                -areaBitangent * areaHalfSize.y,
                areaTangent * areaHalfSize.x + areaBitangent * areaHalfSize.y,
                areaTangent * areaHalfSize.x - areaBitangent * areaHalfSize.y,
                -areaTangent * areaHalfSize.x + areaBitangent * areaHalfSize.y,
                -areaTangent * areaHalfSize.x - areaBitangent * areaHalfSize.y
            );

            specular = vec3(0.0);
            float sampleWeight = 0.0;
            for (int s = 0; s < 9; ++s) {
                vec3 samplePos = areaCenter + sampleOffsets[s];
                vec3 sampleVec = samplePos - FragPos;
                float sampleDist = length(sampleVec);
                if (sampleDist < 1e-4) continue;
                vec3 sampleL = sampleVec / sampleDist;
                float sampleFacing = max(dot(areaNormal, -sampleL), 0.0);
                if (sampleFacing <= 0.0) continue;

                float sampleAtten = attenuation;
                float range = lightRangeArr[i];
                if (range > 0.0) {
                    float falloff = clamp(1.0 - (sampleDist / range), 0.0, 1.0);
                    sampleAtten *= falloff * falloff;
                }

                specular += evaluateDirectSpecular(
                    norm, viewDir, sampleL, F0,
                    roughness, smoothness,
                    specPower, specEnergy,
                    lightColorArr[i], intensity
                ) * sampleAtten * sampleFacing;
                sampleWeight += 1.0;
            }
            if (sampleWeight > 0.0) {
                specular /= sampleWeight;
            }
        } else {
            specular = evaluateDirectSpecular(
                norm, viewDir, lDirN, F0,
                roughness, smoothness,
                specPower, specEnergy,
                lightColorArr[i], intensity
            );
            specular *= attenuation;
        }

        float shadow = 0.0;
        if (lightShadowKindArr[i] != 0) {
            shadow = computeShadowOcclusion(i, FragPos - lightPosArr[i], nl, FragPos);
        }

        lighting += (1.0 - shadow) * (attenuation * diffuse + specular);
    }

    if (hasReflectionCast && reflectionIntensity > 0.0) {
        vec3 reflectionDir = reflect(-viewDir, norm);
        float distanceFade = smoothstep(reflectionFadeStart, max(reflectionFadeStart + 0.01, reflectionFadeEnd), length(viewPos - FragPos));
        float fresnel = pow(1.0 - clamp(dot(norm, viewDir), 0.0, 1.0), 5.0);
        float reflectivity = smoothness * mix(0.18, 1.0, distanceFade) * mix(0.35, 1.0, fresnel);
        vec3 reflected = texture(reflectionCube, reflectionDir).rgb;
        lighting = mix(lighting, reflected, clamp(reflectivity * reflectionIntensity, 0.0, 1.0));
    }

    vec3 finalColor = pow(max(lighting, vec3(0.0)), vec3(1.0 / 2.2));
    finalColor = applyFog(finalColor);
    FragColor = vec4(finalColor, alpha);
}
