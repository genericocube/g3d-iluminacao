// feito por generico_cube
// Directional shadow-map pass. Geometry depth testing is provided by LÖVE.

#ifdef VERTEX
uniform highp mat4 modelMatrix;
uniform highp mat4 lightViewProjection;

vec4 position(mat4 transformProjection, vec4 vertexPosition)
{
    // No y flip here: the shadow map is only ever read back by lighting.glsl with the same
    // light matrix, so writing and reading in the GPU's native orientation keeps them in sync.
    // (Flipping only the write mirrored every shadow around the center of the shadow box,
    // and that center moves with the camera, so shadows seemed to slide while moving.)
    return lightViewProjection * modelMatrix * vertexPosition;
}
#endif // VERTEX

#ifdef PIXEL
vec4 packDepth(float depth)
{
    const vec4 bitShift = vec4(1.0, 255.0, 65025.0, 16581375.0);
    const vec4 bitMask = vec4(1.0/255.0, 1.0/255.0, 1.0/255.0, 0.0);

    vec4 encodedDepth = fract(depth * bitShift);
    encodedDepth -= encodedDepth.yzww * bitMask;
    return encodedDepth;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    return packDepth(gl_FragCoord.z);
}
#endif // PIXEL
