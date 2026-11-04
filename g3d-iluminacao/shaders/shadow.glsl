// feito por generico_cube
// Directional shadow-map pass. Geometry depth testing is provided by LÖVE.

uniform highp mat4 modelMatrix;
uniform highp mat4 lightViewProjection;

vec4 position(mat4 transformProjection, vec4 vertexPosition)
{
    vec4 clipPosition = lightViewProjection * modelMatrix * vertexPosition;

    // LÖVE render-to-canvas targets have vertically flipped texture coordinates.
    clipPosition.y = -clipPosition.y;
    return clipPosition;
}

vec4 packDepth(float depth)
{
    const vec4 bitShift = vec4(1.0, 255.0, 65025.0, 16581375.0);
    const vec4 bitMask = vec4(1.0/255.0, 1.0/255.0, 1.0/255.0, 0.0);

    vec4 packed = fract(depth * bitShift);
    packed -= packed.yzww * bitMask;
    return packed;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    return packDepth(gl_FragCoord.z);
}
