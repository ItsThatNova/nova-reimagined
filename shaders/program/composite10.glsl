/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

// SMAA Pass 3 — Neighbourhood Blending
// Reads:  colortex3  (post-TAA color), colortex10 (blend weights)
// Writes: colortex3  (final antialiased output)

//Common//
#include "/lib/common.glsl"

//////////Fragment Shader//////////Fragment Shader//////////Fragment Shader//////////
#ifdef FRAGMENT_SHADER

noperspective in vec2 texCoord;
noperspective in vec4 smaaOffset;

uniform sampler2D colortex3;  // color input
uniform sampler2D colortex8; // blend weights

//Common Variables//
vec2 view = vec2(viewWidth, viewHeight);
#define SMAA_RT_METRICS vec4(1.0 / viewWidth, 1.0 / viewHeight, viewWidth, viewHeight)

//Includes//
#ifdef SMAA
    #include "/lib/antialiasing/smaa.glsl"
#endif

//Program//
void main() {
    #ifdef SMAA
        vec4 color = SMAANeighborhoodBlendingPS(texCoord, smaaOffset, colortex3, colortex8);
        /* DRAWBUFFERS:3 */
        gl_FragData[0] = color;
    #else
        /* DRAWBUFFERS:3 */
        gl_FragData[0] = texture2D(colortex3, texCoord);
    #endif
}

#endif

//////////Vertex Shader//////////Vertex Shader//////////Vertex Shader//////////
#ifdef VERTEX_SHADER

noperspective out vec2 texCoord;
noperspective out vec4 smaaOffset;

//Common Variables//
vec2 view = vec2(viewWidth, viewHeight);
#define SMAA_RT_METRICS vec4(1.0 / viewWidth, 1.0 / viewHeight, viewWidth, viewHeight)

//Includes//
#ifdef SMAA
    #include "/lib/antialiasing/smaa.glsl"
#endif

//Program//
void main() {
    gl_Position = ftransform();
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    #ifdef SMAA
        SMAANeighborhoodBlendingVS(texCoord, smaaOffset);
    #endif
}

#endif
