/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

// SMAA Pass 1 — Luma Edge Detection
// Reads:  colortex3 (post-TAA gamma-corrected color)
// Writes: colortex9 (RG8 edge buffer)

//Common//
#include "/lib/common.glsl"

//////////Fragment Shader//////////Fragment Shader//////////Fragment Shader//////////
#ifdef FRAGMENT_SHADER

noperspective in vec2 texCoord;
noperspective in vec4 smaaOffset[3];

uniform sampler2D colortex3;

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
        vec2 edges = SMAALumaEdgeDetectionPS(texCoord, smaaOffset, colortex3, depthtex0);
        /* DRAWBUFFERS:9 */
        gl_FragData[0] = vec4(edges, 0.0, 1.0);
    #else
        /* DRAWBUFFERS:9 */
        gl_FragData[0] = vec4(0.0);
    #endif
}

#endif

//////////Vertex Shader//////////Vertex Shader//////////Vertex Shader//////////
#ifdef VERTEX_SHADER

noperspective out vec2 texCoord;
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
        SMAAEdgeDetectionVS(texCoord, smaaOffset);
    #endif
}

#endif
