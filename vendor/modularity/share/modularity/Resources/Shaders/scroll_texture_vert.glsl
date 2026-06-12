#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec2 aTexCoord;
layout (location = 3) in ivec4 aBoneIds;
layout (location = 4) in vec4 aBoneWeights;

out vec3 FragPos;
out vec3 Normal;
out vec2 TexCoord;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform mat4 bones[128];
uniform int boneCount;
uniform bool useSkinning;

void main()
{
    vec4 localPos = vec4(aPos, 1.0);
    vec3 localNormal = aNormal;

    if (useSkinning) {
        vec4 skinnedPos = vec4(0.0);
        vec3 skinnedNormal = vec3(0.0);
        for (int i = 0; i < 4; ++i) {
            int id = aBoneIds[i];
            float w = aBoneWeights[i];
            if (w <= 0.0 || id < 0 || id >= boneCount) continue;
            mat4 b = bones[id];
            skinnedPos += (b * localPos) * w;
            skinnedNormal += mat3(b) * localNormal * w;
        }
        localPos = skinnedPos;
        localNormal = skinnedNormal;
    }

    vec4 worldPos = model * localPos;
    FragPos = vec3(worldPos);
    Normal = mat3(transpose(inverse(model))) * localNormal;
    TexCoord = aTexCoord;
    gl_Position = projection * view * worldPos;
}
