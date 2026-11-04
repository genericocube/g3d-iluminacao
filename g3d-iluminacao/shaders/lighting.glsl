// feito por generico_cube
// Per-pixel lighting for g3d:
//   - sun (directional light) with soft shadow-map shadows (PCF 1, 3x3 or 5x5)
//   - point, spot and directional "fill" lights (MAX_LIGHTS at once)
//   - hemisphere ambient, rim light, toon (cel) shading, fog and exposure
// MAX_LIGHTS is defined by Lua before this file is compiled.

#ifndef MAX_LIGHTS
#define MAX_LIGHTS 16
#endif

// Vertex-stage uniforms: transforms are only needed to build world/clip positions.
#ifdef VERTEX
uniform highp mat4 modelMatrix;
uniform highp mat4 viewMatrix;
uniform highp mat4 projectionMatrix;
uniform highp mat4 lightViewProjection;
uniform float isCanvasEnabled;

attribute vec3 VertexNormal;
#endif

// Pixel-stage uniforms: lighting and material data are only used for shading.
#ifdef PIXEL
uniform Image shadowMap;
uniform highp vec2 shadowTexelSize;
uniform highp vec3 lightDirection;     // direction the sun light travels
uniform highp vec3 directionalColor;
uniform highp float directionalIntensity;
uniform highp vec3 ambientColor;       // sky color (or flat ambient)
uniform highp vec3 ambientGround;      // ground color, same as ambientColor when no hemisphere
uniform highp vec3 cameraPosition;

// local lights, packed by Lua (only the first lightCount entries are valid)
uniform highp float lightCount;
uniform highp vec4 lightA[MAX_LIGHTS];  // xyz = position, w = range
uniform highp vec4 lightB[MAX_LIGHTS];  // rgb = color * intensity, w = type (0 point, 1 spot, 2 directional)
uniform highp vec4 lightC[MAX_LIGHTS];  // xyz = direction the light travels, w = cos(outer angle)
uniform highp float lightD[MAX_LIGHTS]; // 1 / (cos(inner) - cos(outer)), spot lights only

uniform highp float shadowBias;
uniform highp float shadowStrength;
uniform highp float shadowPcf;          // 0 = 1 tap, 1 = 3x3, 2 = 5x5
uniform float shadowsEnabled;
uniform float receivesShadows;

uniform highp float materialSpecularStrength;
uniform highp float materialShininess;
uniform highp vec3 emissiveColor;
uniform highp float emissiveStrength;

uniform highp float toonSteps;          // 0 = off
uniform highp vec3 rimColor;
uniform highp vec2 rimSettings;         // x = power, y = strength (0 = off)
uniform highp vec3 fogColor;
uniform highp vec2 fogRange;            // x = near, y = far (y <= x = off)
uniform highp float exposure;
#endif

// Explicit matching precision prevents GLES vertex/pixel varying mismatches.
varying highp vec3 vWorldPosition;
varying highp vec3 vWorldNormal;
varying highp vec2 vTexCoord;
varying highp vec4 vVertexColor;
varying highp vec4 vShadowPosition;

#ifdef VERTEX
mat3 getNormalMatrix(mat4 transform)
{
    mat3 m = mat3(transform);
    vec3 a = m[0];
    vec3 b = m[1];
    vec3 c = m[2];
    float determinant = dot(a, cross(b, c));

    if (abs(determinant) < 0.000001)
        return m;

    return mat3(cross(b, c), cross(c, a), cross(a, b)) / determinant;
}

vec4 position(mat4 transformProjection, vec4 vertexPosition)
{
    vec4 worldPosition = modelMatrix * vertexPosition;

    vWorldPosition = worldPosition.xyz;
    vWorldNormal = normalize(getNormalMatrix(modelMatrix) * VertexNormal);
    vTexCoord = VertexTexCoord.xy;
    vVertexColor = VertexColor;
    vShadowPosition = lightViewProjection * worldPosition;

    vec4 clipPosition = projectionMatrix * viewMatrix * worldPosition;
    if (isCanvasEnabled > 0.5)
        clipPosition.y = -clipPosition.y;

    return clipPosition;
}
#endif // VERTEX

#ifdef PIXEL
float unpackDepth(vec4 packedDepth)
{
    return dot(packedDepth, vec4(1.0, 1.0/255.0, 1.0/65025.0, 1.0/16581375.0));
}

float shadowTap(vec2 uv, float currentDepth, float bias)
{
    float closestDepth = unpackDepth(Texel(shadowMap, uv));
    return currentDepth - bias > closestDepth ? 1.0 : 0.0;
}

// returns how much the sun is blocked, from 0 (fully lit) to shadowStrength
float calculateShadow(vec3 normal, vec3 toLight)
{
    if (vShadowPosition.w <= 0.0)
        return 0.0;

    vec3 projected = vShadowPosition.xyz / vShadowPosition.w;
    vec2 uv = projected.xy * 0.5 + vec2(0.5);
    float currentDepth = projected.z * 0.5 + 0.5;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 ||
        currentDepth < 0.0 || currentDepth > 1.0)
        return 0.0;

    float bias = shadowBias * max(1.0 - dot(normal, toLight), 0.2);
    float shadow = 0.0;

    if (shadowPcf < 0.5)
    {
        shadow = shadowTap(uv, currentDepth, bias);
    }
    else if (shadowPcf < 1.5)
    {
        // 3x3 kernel
        for (int x = -1; x <= 1; x++)
            for (int y = -1; y <= 1; y++)
                shadow += shadowTap(uv + vec2(float(x), float(y)) * shadowTexelSize, currentDepth, bias);
        shadow /= 9.0;
    }
    else
    {
        // 5x5 kernel
        for (int x = -2; x <= 2; x++)
            for (int y = -2; y <= 2; y++)
                shadow += shadowTap(uv + vec2(float(x), float(y)) * shadowTexelSize, currentDepth, bias);
        shadow /= 25.0;
    }

    // fade the shadow out near the edge of the shadow map instead of cutting it off
    float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    return shadow * shadowStrength * clamp(edge * 12.0, 0.0, 1.0);
}

// adds one light's diffuse and specular contribution
void addLight(vec3 toLight, vec3 color, float attenuation, vec3 normal, vec3 viewDirection,
              inout vec3 diffuse, inout vec3 specular)
{
    float nl = max(dot(normal, toLight), 0.0);
    if (nl <= 0.0 || attenuation <= 0.0)
        return;

    float spec = pow(max(dot(normal, normalize(toLight + viewDirection)), 0.0),
                     max(materialShininess, 1.0));

    if (toonSteps > 0.5)
    {
        nl = ceil(nl * toonSteps) / toonSteps;
        spec = step(0.5, spec);
    }

    diffuse += color * (nl * attenuation);
    specular += color * (spec * materialSpecularStrength * attenuation);
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec4 texel = Texel(texture, vTexCoord);
    vec3 albedo = texel.rgb * vVertexColor.rgb * color.rgb;
    vec3 normal = normalize(vWorldNormal);
    vec3 toCamera = cameraPosition - vWorldPosition;
    float cameraDistance = length(toCamera);
    vec3 viewDirection = toCamera / max(cameraDistance, 0.0001);

    vec3 diffuse = vec3(0.0);
    vec3 specular = vec3(0.0);

    // sun
    vec3 toSun = normalize(-lightDirection);
    float sunVisibility = 1.0;
    if (shadowsEnabled > 0.5 && receivesShadows > 0.5 && dot(normal, toSun) > 0.0)
        sunVisibility = 1.0 - calculateShadow(normal, toSun);
    addLight(toSun, directionalColor * directionalIntensity, sunVisibility,
             normal, viewDirection, diffuse, specular);

    // point, spot and directional fill lights
    for (int i = 0; i < MAX_LIGHTS; i++)
    {
        if (float(i) >= lightCount)
            break;

        vec4 a = lightA[i];
        vec4 b = lightB[i];

        if (b.w > 1.5)
        {
            // directional fill light: no position, no falloff, no shadows
            addLight(normalize(-lightC[i].xyz), b.rgb, 1.0, normal, viewDirection, diffuse, specular);
        }
        else
        {
            vec3 toLight = a.xyz - vWorldPosition;
            float distanceSquared = dot(toLight, toLight);
            float rangeSquared = a.w * a.w;

            if (distanceSquared < rangeSquared)
            {
                float lightDistance = sqrt(distanceSquared);
                vec3 direction = toLight / max(lightDistance, 0.0001);

                // smooth falloff that reaches exactly zero at the light's range
                float attenuation = 1.0 - distanceSquared / rangeSquared;
                attenuation *= attenuation;

                if (b.w > 0.5)
                {
                    // spot cone: smooth edge between the inner and outer angles
                    float cone = clamp((dot(-direction, lightC[i].xyz) - lightC[i].w) * lightD[i], 0.0, 1.0);
                    attenuation *= cone * cone * (3.0 - 2.0 * cone);
                }

                addLight(direction, b.rgb, attenuation, normal, viewDirection, diffuse, specular);
            }
        }
    }

    // hemisphere ambient: sky color on top-facing surfaces, ground color on bottom-facing ones
    vec3 ambient = mix(ambientGround, ambientColor, normal.z * 0.5 + 0.5);
    vec3 result = albedo * (ambient + diffuse) + specular;

    if (rimSettings.y > 0.0)
    {
        float rim = pow(1.0 - max(dot(normal, viewDirection), 0.0), max(rimSettings.x, 0.1));
        result += rimColor * (rim * rimSettings.y);
    }

    result += emissiveColor * emissiveStrength;
    result *= exposure;

    if (fogRange.y > fogRange.x)
    {
        float fog = clamp((cameraDistance - fogRange.x) / (fogRange.y - fogRange.x), 0.0, 1.0);
        result = mix(result, fogColor, fog);
    }

    return vec4(result, texel.a * vVertexColor.a * color.a);
}
#endif // PIXEL
