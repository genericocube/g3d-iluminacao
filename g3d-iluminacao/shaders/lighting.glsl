// feito por generico_cube
// Per-pixel directional + point lighting with PCF directional shadows.

#define MAX_POINT_LIGHTS 4

// Vertex-stage uniforms: transforms are only needed to build world/clip positions.
#ifdef VERTEX
uniform highp mat4 modelMatrix;
uniform highp mat4 viewMatrix;
uniform highp mat4 projectionMatrix;
uniform highp mat4 lightViewProjection;
uniform bool isCanvasEnabled;

attribute vec3 VertexNormal;
#endif

// Pixel-stage uniforms: lighting and material data are only used for shading.
#ifdef PIXEL
uniform Image shadowMap;
uniform highp vec2 shadowTexelSize;
uniform highp vec3 lightDirection;
uniform highp vec3 directionalColor;
uniform highp float directionalIntensity;
uniform highp vec3 ambientColor;
uniform highp vec3 cameraPosition;

uniform highp vec3 pointPosition[MAX_POINT_LIGHTS];
uniform highp vec3 pointColor[MAX_POINT_LIGHTS];
uniform highp float pointIntensity[MAX_POINT_LIGHTS];
uniform highp float pointRange[MAX_POINT_LIGHTS];

uniform highp float shadowBias;
uniform highp float shadowStrength;
uniform bool shadowsEnabled;
uniform bool receivesShadows;

uniform highp float materialSpecularStrength;
uniform highp float materialShininess;
uniform highp vec3 emissiveColor;
uniform highp float emissiveStrength;
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
#endif // VERTEX

#ifdef VERTEX
vec4 position(mat4 transformProjection, vec4 vertexPosition)
{
    vec4 worldPosition = modelMatrix * vertexPosition;

    vWorldPosition = worldPosition.xyz;
    vWorldNormal = normalize(getNormalMatrix(modelMatrix) * VertexNormal);
    vTexCoord = VertexTexCoord.xy;
    vVertexColor = VertexColor;
    vShadowPosition = lightViewProjection * worldPosition;

    vec4 clipPosition = projectionMatrix * viewMatrix * worldPosition;
    if (isCanvasEnabled)
        clipPosition.y = -clipPosition.y;

    return clipPosition;
}

#endif // VERTEX

#ifdef PIXEL
float unpackDepth(vec4 packedDepth)
{
    return dot(packedDepth, vec4(1.0, 1.0/255.0, 1.0/65025.0, 1.0/16581375.0));
}

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

    // Fixed 3x3 PCF kernel: predictable cost and smoother shadow edges.
    for (int x = -1; x <= 1; x++)
    {
        for (int y = -1; y <= 1; y++)
        {
            vec2 offset = vec2(float(x), float(y)) * shadowTexelSize;
            float closestDepth = unpackDepth(Texel(shadowMap, uv + offset));
            shadow += currentDepth - bias > closestDepth ? 1.0 : 0.0;
        }
    }

    return (shadow / 9.0) * shadowStrength;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec4 texel = Texel(texture, vTexCoord);
    vec3 albedo = texel.rgb * vVertexColor.rgb * color.rgb;
    vec3 normal = normalize(vWorldNormal);
    vec3 viewDirection = normalize(cameraPosition - vWorldPosition);

    vec3 toDirectionalLight = normalize(-lightDirection);
    float directionalDiffuse = max(dot(normal, toDirectionalLight), 0.0);
    float directionalShadow = 0.0;

    if (shadowsEnabled && receivesShadows && directionalDiffuse > 0.0)
        directionalShadow = calculateShadow(normal, toDirectionalLight);

    float directionalVisibility = 1.0 - directionalShadow;
    vec3 result = albedo * ambientColor;

    vec3 directionalHalf = normalize(toDirectionalLight + viewDirection);
    float directionalSpecular = pow(
        max(dot(normal, directionalHalf), 0.0),
        max(materialShininess, 1.0)
    ) * materialSpecularStrength;

    result += albedo * directionalColor *
        (directionalDiffuse * directionalIntensity * directionalVisibility);
    result += directionalColor *
        (directionalSpecular * directionalIntensity * directionalVisibility);

    for (int i = 0; i < MAX_POINT_LIGHTS; i++)
    {
        float range = max(pointRange[i], 0.001);
        vec3 toPoint = pointPosition[i] - vWorldPosition;
        float distanceToPoint = length(toPoint);

        if (distanceToPoint < range && pointIntensity[i] > 0.0)
        {
            vec3 pointDirection = toPoint / max(distanceToPoint, 0.0001);
            float attenuation = 1.0 - distanceToPoint / range;
            attenuation *= attenuation;

            float diffuse = max(dot(normal, pointDirection), 0.0);
            vec3 pointHalf = normalize(pointDirection + viewDirection);
            float specular = pow(
                max(dot(normal, pointHalf), 0.0),
                max(materialShininess, 1.0)
            ) * materialSpecularStrength;

            float strength = attenuation * pointIntensity[i];
            result += albedo * pointColor[i] * diffuse * strength;
            result += pointColor[i] * specular * strength;
        }
    }

    result += emissiveColor * emissiveStrength;
    return vec4(result, texel.a * vVertexColor.a * color.a);
}
#endif // PIXEL
