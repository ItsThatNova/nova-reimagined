/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

// SMAA Pass 2 — Blending Weight Calculation
// Reads:  colortex9  (edges), colortex11 (areaTex), colortex12 (searchTex)
// Writes: colortex10 (RGBA8 blend weight buffer)

//Common//
#include "/lib/common.glsl"

//////////Fragment Shader//////////Fragment Shader//////////Fragment Shader//////////
#ifdef FRAGMENT_SHADER

noperspective in vec2 texCoord;
noperspective in vec2 smaaPixCoord;
noperspective in vec4 smaaOffset[3];

uniform sampler2D colortex9;  // edges input
uniform sampler2D colortex11; // areaTex
uniform sampler2D colortex12; // searchTex

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
        vec4 weights = SMAABlendingWeightCalculationPS(
            texCoord, smaaPixCoord, smaaOffset,
            colortex9,  // edgesTex
            colortex11, // areaTex
            colortex12, // searchTex
            vec4(0.0)   // subsampleIndices — vec4(0) for SMAA 1x
        );
        /* DRAWBUFFERS:8 */
        gl_FragData[0] = weights;
    #else
        /* DRAWBUFFERS:8 */
        gl_FragData[0] = vec4(0.0);
    #endif
}

#endif

//////////Vertex Shader//////////Vertex Shader//////////Vertex Shader//////////
#ifdef VERTEX_SHADER

noperspective out vec2 texCoord;
noperspective out vec2 smaaPixCoord;
noperspective out vec4 smaaOffset[3];

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
        SMAABlendingWeightCalculationVS(texCoord, smaaPixCoord, smaaOffset);
    #endif
}

#endif
