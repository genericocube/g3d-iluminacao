// per-pixel Blinn-Phong lighting for g3d
// one directional light (the "sun") + up to MAX_LIGHTS point lights

#define MAX_LIGHTS 8

varying vec4 worldPosition;
varying vec3 worldNormal;

uniform vec3 cameraPosition;
uniform vec3 ambientColor;
uniform vec3 sunDirection;  // direction the light travels (from the sun towards the scene)
uniform vec3 sunColor;      // already multiplied by intensity, black = off
uniform int lightCount;
uniform vec3 lightPositions[MAX_LIGHTS];
uniform vec3 lightColors[MAX_LIGHTS]; // already multiplied by intensity
uniform float lightRadii[MAX_LIGHTS];
uniform float shininess;
uniform float specularStrength;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screenCoords) {
    vec4 base = Texel(tex, uv) * color;

    vec3 N = normalize(worldNormal);
    vec3 V = normalize(cameraPosition - worldPosition.xyz);

    vec3 diffuse = ambientColor;
    vec3 specular = vec3(0.0);

    // sun
    if (dot(sunColor, vec3(1.0)) > 0.0) {
        vec3 L = normalize(-sunDirection);
        float nl = max(dot(N, L), 0.0);
        diffuse += sunColor * nl;
        if (nl > 0.0) {
            vec3 H = normalize(L + V);
            specular += sunColor * pow(max(dot(N, H), 0.0), shininess);
        }
    }

    // point lights, smooth falloff that reaches exactly zero at the light's radius
    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= lightCount) break;

        vec3 toLight = lightPositions[i] - worldPosition.xyz;
        float dist = length(toLight);
        float r = max(lightRadii[i], 0.0001);
        float att = clamp(1.0 - (dist * dist) / (r * r), 0.0, 1.0);
        att *= att;
        if (att <= 0.0) continue;

        vec3 L = toLight / max(dist, 0.0001);
        float nl = max(dot(N, L), 0.0);
        diffuse += lightColors[i] * nl * att;
        if (nl > 0.0) {
            vec3 H = normalize(L + V);
            specular += lightColors[i] * pow(max(dot(N, H), 0.0), shininess) * att;
        }
    }

    return vec4(base.rgb * diffuse + specular * specularStrength, base.a);
}
