/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

//Common//
#include "/lib/common.glsl"

//////////Fragment Shader//////////Fragment Shader//////////Fragment Shader//////////
#ifdef FRAGMENT_SHADER

flat in int mat;

in vec2 lmCoord;

flat in vec3 upVec, sunVec, northVec, eastVec;
in vec3 normal;
in vec3 playerPos;
in vec3 viewVector;

in vec4 glColor;

//Pipeline Constants//

//Common Variables//
float NdotU = dot(normal, upVec);
float NdotUmax0 = max(NdotU, 0.0);
float SdotU = dot(sunVec, upVec);
float sunFactor = SdotU < 0.0 ? clamp(SdotU + 0.375, 0.0, 0.75) / 0.75 : clamp(SdotU + 0.03125, 0.0, 0.0625) / 0.0625;
float sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
float sunVisibility2 = sunVisibility * sunVisibility;
float shadowTimeVar1 = abs(sunVisibility - 0.5) * 2.0;
float shadowTimeVar2 = shadowTimeVar1 * shadowTimeVar1;
float shadowTime = shadowTimeVar2 * shadowTimeVar2;

vec2 lmCoordM = lmCoord;

mat4 gbufferProjection = dhProjection;
mat4 gbufferProjectionInverse = dhProjectionInverse;

#ifdef OVERWORLD
    vec3 lightVec = sunVec * ((timeAngle < 0.5325 || timeAngle > 0.9675) ? 1.0 : -1.0);
#else
    vec3 lightVec = sunVec;
#endif

#if WATER_STYLE >= 2 || RAIN_PUDDLES >= 1 && WATER_STYLE == 1 && WATER_MAT_QUALITY >= 2 || defined GENERATED_NORMALS || defined CUSTOM_PBR
    mat3 tbnMatrix = mat3(
        eastVec.x, northVec.x, normal.x,
        eastVec.y, northVec.y, normal.y,
        eastVec.z, northVec.z, normal.z
    );
#endif

//Common Functions//

//Includes//
#include "/lib/util/dither.glsl"
#include "/lib/util/spaceConversion.glsl"
#include "/lib/lighting/mainLighting.glsl"
#include "/lib/atmospherics/fog/mainFog.glsl"

// Complementary Snow mod — biome intensity map for snow-covered ice
uniform sampler2D snowBiomeMap;
uniform sampler2D snowBiomeMeta;

float sampleSnowBiomeWater(vec3 pos) {
    vec4 meta = texelFetch(snowBiomeMeta, ivec2(0), 0);
    if (meta.a < 0.5) return 0.0;
    float size = pow(2.0, meta.r * 5.0 + 5.0);
    vec3 worldPos = pos + cameraPosition;
    ivec2 chunkCoord = ivec2(floor(worldPos.xz / 16.0));
    ivec2 tc = ivec2(mod(vec2(chunkCoord), size));
    float snowCurrent = texelFetch(snowBiomeMap, tc, 0).r;

    float snowPX = texelFetch(snowBiomeMap, ivec2(mod(vec2(chunkCoord + ivec2( 1, 0)), size)), 0).r;
    float snowNX = texelFetch(snowBiomeMap, ivec2(mod(vec2(chunkCoord + ivec2(-1, 0)), size)), 0).r;
    float snowPZ = texelFetch(snowBiomeMap, ivec2(mod(vec2(chunkCoord + ivec2( 0, 1)), size)), 0).r;
    float snowNZ = texelFetch(snowBiomeMap, ivec2(mod(vec2(chunkCoord + ivec2( 0,-1)), size)), 0).r;

    float maxNeighbour = max(max(snowPX, snowNX), max(snowPZ, snowNZ));
    if (maxNeighbour <= snowCurrent) return snowCurrent;

    float noise1 = texture2DLod(noisetex, worldPos.xz / 32.0, 0.0).r;
    float noise2 = texture2DLod(noisetex, worldPos.xz / 16.0 + vec2(0.3, 0.7), 0.0).r;
    float noise  = noise1 * 0.65 + noise2 * 0.35;

    float overdrawFrac = (4.0 + noise * 6.0) / 16.0;

    vec2  chunkFrac = fract(worldPos.xz / 16.0);
    float proximity = 0.0;
    if (snowPX > snowCurrent) proximity = max(proximity, clamp((1.0 - (1.0 - chunkFrac.x) / overdrawFrac), 0.0, 1.0) * (snowPX - snowCurrent));
    if (snowNX > snowCurrent) proximity = max(proximity, clamp((1.0 - chunkFrac.x         / overdrawFrac), 0.0, 1.0) * (snowNX - snowCurrent));
    if (snowPZ > snowCurrent) proximity = max(proximity, clamp((1.0 - (1.0 - chunkFrac.y) / overdrawFrac), 0.0, 1.0) * (snowPZ - snowCurrent));
    if (snowNZ > snowCurrent) proximity = max(proximity, clamp((1.0 - chunkFrac.y         / overdrawFrac), 0.0, 1.0) * (snowNZ - snowCurrent));

    proximity = floor(clamp(proximity, 0.0, 1.0) * 4.0) / 4.0;
    return min(1.0, snowCurrent + proximity);
}

#ifdef TAA
    #include "/lib/antialiasing/jitter.glsl"
#endif

#ifdef OVERWORLD
    #include "/lib/atmospherics/sky.glsl"
#endif

#if WATER_REFLECT_QUALITY >= 0
    #if defined SKY_EFFECT_REFLECTION && defined OVERWORLD
        #if AURORA_STYLE > 0
            #include "/lib/atmospherics/auroraBorealis.glsl"
        #endif

        #if NIGHT_NEBULAE == 1
            #include "/lib/atmospherics/nightNebula.glsl"
        #else
            #include "/lib/atmospherics/stars.glsl"
        #endif

        #ifdef VL_CLOUDS_ACTIVE 
            #include "/lib/atmospherics/clouds/mainClouds.glsl"
        #endif
    #endif

    #include "/lib/materials/materialMethods/reflections.glsl"
#endif

#ifdef ATM_COLOR_MULTS
    #include "/lib/colors/colorMultipliers.glsl"
#endif
#ifdef MOON_PHASE_INF_ATMOSPHERE
    #include "/lib/colors/moonPhaseInfluence.glsl"
#endif

//Program//
void main() {
    vec4 colorP = vec4(vec3(0.85), glColor.a);
    vec4 color = glColor;

    vec3 screenPos = vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z);
    if (texture2D(depthtex1, screenPos.xy).r < 1.0) discard;
    float lViewPos = length(playerPos);

    float dither = Bayer64(gl_FragCoord.xy);
    #ifdef TAA
        dither = fract(dither + goldenRatio * mod(float(frameCounter), 3600.0));
    #endif

    #ifdef ATM_COLOR_MULTS
        atmColorMult = GetAtmColorMult();
        sqrtAtmColorMult = sqrt(atmColorMult);
    #endif

    #ifdef VL_CLOUDS_ACTIVE
        float cloudLinearDepth = texelFetch(gaux2, texelCoord, 0).a;

        if (pow2(cloudLinearDepth + OSIEBCA * dither) * renderDistance < min(lViewPos, renderDistance)) discard;
    #endif

    #ifdef TAA
        vec3 viewPos = ScreenToView(vec3(TAAJitter(screenPos.xy, -0.5), screenPos.z));
    #else
        vec3 viewPos = ScreenToView(screenPos);
    #endif
    vec3 nViewPos = normalize(viewPos);
    float VdotU = dot(nViewPos, upVec);
    float VdotS = dot(nViewPos, sunVec);

    bool noSmoothLighting = false, noDirectionalShading = false, noVanillaAO = false, centerShadowBias = false;
    int subsurfaceMode = 0;
    float smoothnessG = 0.0, highlightMult = 0.0, emission = 0.0, materialMask = 0.0, reflectMult = 0.0;
    vec3 normalM = normal, geoNormal = normal, shadowMult = vec3(1.0);
    vec3 worldGeoNormal = normalize(ViewToPlayer(geoNormal * 10000.0));
    float fresnel = clamp(1.0 + dot(normalM, nViewPos), 0.0, 1.0);

    if (mat == DH_BLOCK_WATER) {
        #include "/lib/materials/specificMaterials/translucents/water.glsl"
        color.rgb *= vec3(DH_WATER_R, DH_WATER_G, DH_WATER_B);
        float dhLuma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        color.rgb = mix(vec3(dhLuma), color.rgb, DH_WATER_SAT);
        color.a = min(color.a, DH_WATER_ALPHA);
    }
    
    float fresnelM = (pow3(fresnel) * 0.85 + 0.15) * reflectMult * WATER_REFLECT_I;

    float lengthCylinder = max(length(playerPos.xz), abs(playerPos.y) * 2.0);
    #ifdef DH_OVERDRAW_PROTECTION
        // Hard near cutoff: no DH inside vanilla render space
        float dhNearCutoff = clamp(far - float(DH_OVERDRAW_DISTANCE), 32.0, far);
        if (lengthCylinder < dhNearCutoff) discard;

        // Dither fade-in: DH dissolves in just beyond vanilla render distance
        float dhFade = smoothstep(far * 0.86, far * 0.9, lengthCylinder);
        if (dhFade < dither) discard;
    #endif

    // Snow-covered ice: ice blocks have no DH_BLOCK_ICE constant and fall through
    // the water material check. In snowy chunks, override their appearance to
    // look snow-covered rather than rendering as an unlit dark blue fragment.
    // snowDriver is the real gate — 0.0 when mod inactive or biome not snowy.
    if (mat != DH_BLOCK_WATER) {
        float snowDriver = sampleSnowBiomeWater(playerPos);
        if (snowDriver > 0.01) {
            float upFactor   = max(NdotU, 0.0);
            float sideFactor = (NdotU >= -0.1 && NdotU < 0.5)
                             ? clamp(1.0 - abs(NdotU) * 2.0, 0.0, 1.0) * 0.6
                             : 0.0;
            float snowFactorM = clamp(max(upFactor + sideFactor, 0.0) * 3.5, 0.0, 1.0)
                              * snowDriver;
            if (snowFactorM > 0.0001) {
                vec3 snowColor = vec3(0.85, 0.92, 0.95);
                color.rgb     = mix(color.rgb, snowColor, snowFactorM);
                color.a       = 1.0;
                smoothnessG   = mix(smoothnessG,   0.25, snowFactorM);
                highlightMult = mix(highlightMult, 2.0,  snowFactorM);
                emission     *= 1.0 - snowFactorM * 0.85;
            }
        }
    }

    DoLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, 0.5,
               worldGeoNormal, lmCoordM, noSmoothLighting, noDirectionalShading, noVanillaAO,
               centerShadowBias, subsurfaceMode, smoothnessG, highlightMult, emission);

    // Reflections
    #if WATER_REFLECT_QUALITY >= 0
        #ifdef LIGHT_COLOR_MULTS
            highlightColor *= lightColorMult;
        #endif
        #ifdef MOON_PHASE_INF_REFLECTION
            highlightColor *= pow2(moonPhaseInfluence);
        #endif

        float skyLightFactor = GetSkyLightFactor(lmCoordM, shadowMult);

        vec4 reflection = GetReflection(normalM, viewPos.xyz, nViewPos, playerPos, lViewPos, -1.0,
                                        depthtex1, dither, skyLightFactor, fresnel,
                                        smoothnessG, geoNormal, color.rgb, shadowMult, highlightMult);

        color.rgb = mix(color.rgb, reflection.rgb, fresnelM);
    #endif
    ////

    float sky = 0.0;

    float prevAlpha = color.a;
    DoFog(color, sky, lViewPos, playerPos, VdotU, VdotS, dither, false, 0.0);
    float fogAlpha = color.a;
    color.a = prevAlpha * (1.0 - sky);

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = color;

    #if WORLD_SPACE_REFLECTIONS > 0
        /* DRAWBUFFERS:048 */
        gl_FragData[1] = vec4(mat3(gbufferModelViewInverse) * normalM, sqrt(fresnelM * color.a * fogAlpha));
        gl_FragData[2] = vec4(reflection.rgb * fresnelM * color.a * fogAlpha, reflection.a);
    #endif
}

#endif

//////////Vertex Shader//////////Vertex Shader//////////Vertex Shader//////////
#ifdef VERTEX_SHADER

flat out int mat;

out vec2 lmCoord;

flat out vec3 upVec, sunVec, northVec, eastVec;
out vec3 normal;
out vec3 playerPos;
out vec3 viewVector;

out vec4 glColor;

//Attributes//
attribute vec4 at_tangent;

//Common Variables//

//Common Functions//

//Includes//
#ifdef TAA
    #include "/lib/antialiasing/jitter.glsl"
#endif

//Program//
void main() {
    gl_Position = ftransform();
    #ifdef TAA
        gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
    #endif

    mat = dhMaterialId;

    lmCoord  = GetLightMapCoordinates();
    
    normal = normalize(gl_NormalMatrix * gl_Normal);
    upVec = normalize(gbufferModelView[1].xyz);
    eastVec = normalize(gbufferModelView[0].xyz);
    northVec = normalize(gbufferModelView[2].xyz);
    sunVec = GetSunVector();

    playerPos = (gbufferModelViewInverse * gl_ModelViewMatrix * gl_Vertex).xyz;

    mat3 tbnMatrix = mat3(
        eastVec.x, northVec.x, normal.x,
        eastVec.y, northVec.y, normal.y,
        eastVec.z, northVec.z, normal.z
    );

    viewVector = tbnMatrix * (gl_ModelViewMatrix * gl_Vertex).xyz;

    glColor = gl_Color;
}

#endif