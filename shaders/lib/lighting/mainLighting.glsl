//Lighting Includes//
#include "/lib/colors/lightAndAmbientColors.glsl"
#include "/lib/lighting/ggx.glsl"
#include "/lib/lighting/minimumLighting.glsl"

#if SHADOW_QUALITY > -1 && (defined OVERWORLD || defined END)
    #include "/lib/lighting/shadowSampling.glsl"
#endif

#if HELD_LIGHTING_MODE >= 1
    #include "/lib/lighting/heldLighting.glsl"
#endif

#ifdef CLOUD_SHADOWS
    #include "/lib/lighting/cloudShadows.glsl"
#endif

#ifdef LIGHT_COLOR_MULTS
    #include "/lib/colors/colorMultipliers.glsl"
#endif

#if defined MOON_PHASE_INF_LIGHT || defined MOON_PHASE_INF_REFLECTION
    #include "/lib/colors/moonPhaseInfluence.glsl"
#endif

#if COLORED_LIGHTING_INTERNAL > 0
    #include "/lib/voxelization/lightVoxelization.glsl"
#endif

#ifdef DO_PIXELATION_EFFECTS
    #include "/lib/misc/pixelation.glsl"
#endif

//Cell Lighting Helpers//
#ifdef CELL_LIGHTING

// Quantizes a direct-light intensity into distinct Borderlands-style tonal bands.
//
// Key design: output levels are DISTINCT from input values, forcing large scale
// ratios (quantized/input) at each band boundary. This is what creates clearly
// visible banding -- prior version had outputs proportional to inputs (scale ~1.0)
// which was almost invisible. Each band uses mix() for clean TAA-stable transitions.
//
// Input range: 0.0 (fully shadowed) to ~1.0 (full noon sun).
// Values >1.0 are clamped to the top band by the internal clamp().
float CellQuantize(float intensity) {
    const float w = 0.05; // smoothstep half-width -- narrow enough to read as
                          // a hard band, wide enough to be TAA-stable.

    // Contrast curve: exponent > 1.0 pushes more surface area into shadow bands
    // (Borderlands style). CELL_LIGHTING_CONTRAST 100 = neutral (exponent 1.0).
    float x = pow(clamp(intensity, 0.0, 1.0), CELL_LIGHTING_CONTRAST * 0.01);

    #if CELL_LIGHTING_BANDS == 3
        // Levels: 0.0 / 0.38 / 1.0
        // Bold two-step: deep shadow, then a wide mid that jumps straight to lit.
        // Most graphic of the three options.
        return mix(
            mix(0.0, 0.38, smoothstep(0.18 - w, 0.18 + w, x)),
            1.0, smoothstep(0.62 - w, 0.62 + w, x));

    #elif CELL_LIGHTING_BANDS == 4
        // Levels: 0.0 / 0.25 / 0.62 / 1.0
        // Default. Shadow kills dim surfaces, mid bands create clear tonal steps,
        // highlight pops. Scale ratios: ~1.67 / ~1.38 / ~1.37 at each threshold.
        float t1 = smoothstep(0.14 - w, 0.14 + w, x);
        float t2 = smoothstep(0.44 - w, 0.44 + w, x);
        float t3 = smoothstep(0.72 - w, 0.72 + w, x);
        return mix(mix(mix(0.0, 0.25, t1), 0.62, t2), 1.0, t3);

    #elif CELL_LIGHTING_BANDS == 5
        // Levels: 0.0 / 0.18 / 0.40 / 0.66 / 1.0
        // Most nuanced. Still creates clear steps but denser in the midrange.
        float t1 = smoothstep(0.10 - w, 0.10 + w, x);
        float t2 = smoothstep(0.30 - w, 0.30 + w, x);
        float t3 = smoothstep(0.52 - w, 0.52 + w, x);
        float t4 = smoothstep(0.76 - w, 0.76 + w, x);
        return mix(mix(mix(mix(0.0, 0.18, t1), 0.40, t2), 0.66, t3), 1.0, t4);
    #endif
}

// 2-level quantizer for blocklight (torch/lamp falloff).
// Output levels are used as a ratio multiplier against lightmap.x (see
// application site below), so 0-1 outputs scale lightmapXM proportionally.
// Bottom level 0.08 (not 0.0) keeps distant surfaces from going fully black.
float CellQuantizeBlocklight(float intensity) {
    const float w = 0.07;
    float x = pow(clamp(intensity, 0.0, 1.0), CELL_LIGHTING_CONTRAST * 0.01);
    return mix(
        mix(0.08, 0.42, smoothstep(0.20 - w, 0.20 + w, x)),
        1.0, smoothstep(0.58 - w, 0.58 + w, x));
}

// Returns a modified specular value appropriate for cell lighting mode.
// CELL_LIGHTING_SPECULAR 0 (Off)     -- removes specular entirely.
// CELL_LIGHTING_SPECULAR 1 (Reduced) -- heavily damped GGX, soft sheen only.
// CELL_LIGHTING_SPECULAR 2 (Hard)    -- crisp binary hotspot (Borderlands style).
float CellSpecular(float specularHighlight) {
    #if CELL_LIGHTING_SPECULAR == 0
        return 0.0;
    #elif CELL_LIGHTING_SPECULAR == 1
        return specularHighlight * 0.25;
    #elif CELL_LIGHTING_SPECULAR == 2
        // Binary hotspot: smooth transition around a fixed threshold.
        const float threshold = 0.20;
        const float w = 0.05;
        return smoothstep(threshold - w, threshold + w, specularHighlight);
    #endif
}


// Modifies the ambient lighting contribution based on CELL_LIGHTING_AMBIENT_MODE.
// Takes the computed ambient color vector and returns a modified version.
//   Mode 0 (Smooth)  -- returns ambient unchanged.
//   Mode 1 (Reduced) -- scales ambient down to 55%, dimming the fill so
//                       direct-light bands read more clearly.
//   Mode 2 (Soft)    -- blends 50% quantized + 50% smooth ambient, giving
//                       a hint of banding in the fill without harshness.
//   Mode 3 (Flat)    -- collapses ambient to a single dim constant fill,
//                       maximising band contrast at the cost of realism.
vec3 CellAmbient(vec3 ambientColor) {
    #if CELL_LIGHTING_AMBIENT_MODE == 0
        return ambientColor;

    #elif CELL_LIGHTING_AMBIENT_MODE == 1
        return ambientColor * 0.55;

    #elif CELL_LIGHTING_AMBIENT_MODE == 2
        float ambLum = GetLuminance(ambientColor);
        float ambQuantized = ambLum > 0.001
            ? CellQuantize(ambLum) / ambLum
            : 0.0;
        // Mix 50% quantized, 50% smooth, then reduce a little so bands
        // still read against the partial ambient fill.
        return ambientColor * mix(1.0, ambQuantized, 0.5) * 0.75;

    #elif CELL_LIGHTING_AMBIENT_MODE == 3
        // Collapse to a flat dim fill: preserves the ambient color hue
        // but removes all gradient. 0.18 is tuned to sit just above
        // the bottom band threshold so shadowed surfaces stay readable.
        float ambLum = GetLuminance(ambientColor);
        return ambLum > 0.001
            ? (ambientColor / ambLum) * 0.18
            : vec3(0.0);
    #endif
}
#endif // CELL_LIGHTING

vec3 highlightColor = normalize(pow(lightColor, vec3(0.37))) * (0.3 + 1.5 * sunVisibility2) * (1.0 - 0.85 * rainFactor);

//Lighting//
void DoLighting(inout vec4 color, inout vec3 shadowMult, vec3 playerPos, vec3 viewPos, float lViewPos, vec3 geoNormal, vec3 normalM, float dither,
                vec3 worldGeoNormal, vec2 lightmap, bool noSmoothLighting, bool noDirectionalShading, bool noVanillaAO,
                bool centerShadowBias, int subsurfaceMode, float smoothnessG, float highlightMult, float emission) {
    #ifdef DO_PIXELATION_EFFECTS
        vec2 pixelationOffset = ComputeTexelOffset(tex, texCoord);

        #if defined PIXELATED_SHADOWS || defined PIXELATED_BLOCKLIGHT
            vec3 playerPosPixelated = TexelSnap(playerPos, pixelationOffset);
        #endif

        #ifdef PIXELATED_SHADOWS
            #ifdef GBUFFERS_ENTITIES
                if (entityId == 50076) { // Boats
                    playerPosPixelated.y += 0.38; // consistentBOAT2176
                }
            #endif
            #ifdef GBUFFERS_TERRAIN
                if (subsurfaceMode == 1) {
                    playerPosPixelated.y += 0.05; // Fixes grounded foliage having dark bottom pixels depending on the random y-offset
                }
            #endif
        #endif
        #ifdef PIXELATED_BLOCKLIGHT
            if (!noSmoothLighting) {
                lightmap = clamp(TexelSnap(lightmap, pixelationOffset), 0.0, 1.0);
            }
        #endif
    #endif

    float NdotN = dot(normalM, northVec);
    float absNdotN = abs(NdotN);
    float NdotE = dot(normalM, eastVec);
    float absNdotE = abs(NdotE);
    float NdotL = dot(normalM, lightVec);

    float lightmapY2 = pow2(lightmap.y);
    float lightmapYM = smoothstep1(lightmap.y);
    float subsurfaceHighlight = 0.0;
    float ambientMult = 1.0;
    vec3 lightColorM = lightColor;
    vec3 ambientColorM = ambientColor;
    vec3 nViewPos = normalize(viewPos);

    #if defined LIGHT_COLOR_MULTS && !defined GBUFFERS_WATER // lightColorMult is defined early in gbuffers_water
        lightColorMult = GetLightColorMult();
    #endif

    #ifdef OVERWORLD
        float skyLightShadowMult = pow2(pow2(lightmapY2));
    #else
        float skyLightShadowMult = 1.0;
    #endif

    #if defined CUSTOM_PBR || defined GENERATED_NORMALS
        float NPdotU = abs(dot(geoNormal, upVec));
    #endif

    // Shadows
    #if defined OVERWORLD || defined END
        #ifdef GBUFFERS_WATER
            //NdotL = mix(NdotL, 1.0, 1.0 - color.a);
        #endif
        #ifdef CUSTOM_PBR
            float geoNdotL = dot(geoNormal, lightVec);
            float geoNdotLM = geoNdotL > 0.0 ? geoNdotL * 10.0 : geoNdotL;
            NdotL = min(geoNdotLM, NdotL);

            NdotL *= 1.0 - 0.7 * (1.0 - pow2(pow2(NdotUmax0))) * NPdotU;
        #endif
        #if SHADOW_QUALITY == -1 && defined GBUFFERS_TERRAIN
            if (subsurfaceMode == 1) {
                NdotU = 1.0;
                NdotUmax0 = 1.0;
                NdotL = dot(upVec, lightVec);
            } else if (subsurfaceMode == 2) {
                highlightMult *= NdotL;
                NdotL = mix(NdotL, 1.0, 0.35);
            }

            subsurfaceMode = 0;
        #endif
        float NdotLmax0 = max0(NdotL);
        float NdotLM = NdotLmax0 * 0.9999;

        #ifdef GBUFFERS_TEXTURED
            NdotLM = 1.0;
        #else
            #ifdef GBUFFERS_TERRAIN
                if (subsurfaceMode != 0) {
                    #if defined CUSTOM_PBR && defined POM && POM_QUALITY >= 128 && POM_LIGHTING_MODE == 2
                        shadowMult *= max(pow2(pow2(dot(normalM, geoNormal))), sqrt2(NdotLmax0));
                    #endif
                    NdotLM = 1.0;
                }
                #ifdef SIDE_SHADOWING
                    else
                #endif
            #endif
            #ifdef SIDE_SHADOWING
                NdotLM = max0(NdotL + 0.4) * 0.714;

                #ifdef END
                    NdotLM = sqrt3(NdotLM);
                #endif
            #endif
        #endif

        #if ENTITY_SHADOW == -1 && defined GBUFFERS_ENTITIES || ENTITY_SHADOW <= 1 && defined GBUFFERS_BLOCK
            lightColorM = mix(lightColorM * 0.75, ambientColorM, 0.5 * pow2(pow2(1.0 - NdotLM)));
            NdotLM = NdotLM * 0.75 + 0.25;
        #endif

        if (shadowMult.r > 0.00001) {
            #if SHADOW_QUALITY > -1
                if (NdotLM > 0.0001) {
                    vec3 shadowMultBeforeLighting = shadowMult;

                    #if !defined DH_TERRAIN && !defined DH_WATER
                        float shadowLength = shadowDistance * 0.9166667 - lViewPos; //consistent08JJ622
                    #else
                        float shadowLength = 0.0;
                    #endif

                    if (shadowLength > 0.000001) {
                        #if SHADOW_SMOOTHING == 4 || SHADOW_QUALITY == 0
                            float offset = 0.00098;
                        #elif SHADOW_SMOOTHING == 3
                            float offset = 0.00075;
                        #elif SHADOW_SMOOTHING == 2
                            float offset = 0.0005;
                        #elif SHADOW_SMOOTHING == 1
                            float offset = 0.0003;
                        #endif

                        vec3 playerPosM = playerPos;
                        vec3 centerPlayerPos = floor(playerPos + cameraPosition + worldGeoNormal * 0.01) - cameraPosition + 0.5;

                        #if defined DO_PIXELATION_EFFECTS && defined PIXELATED_SHADOWS
                            playerPosM = playerPosPixelated;
                            offset *= 0.75;
                        #endif

                        // Fix light leaking in caves //
                        #ifdef GBUFFERS_TERRAIN
                            if (centerShadowBias || subsurfaceMode == 1) {
                                #ifdef OVERWORLD
                                    playerPosM = mix(centerPlayerPos, playerPosM, 0.5 + 0.5 * lightmapYM);
                                #endif
                            } else {
                                float centerFactor = max(glColor.a, lightmapYM);

                                #if defined PERPENDICULAR_TWEAKS && SHADOW_QUALITY >= 2 && !defined DH_TERRAIN
                                    // Fake Variable Penumbra Shadows
                                    // Making centerFactor also work in daylight if AO gradient is facing towards sun
                                    if (geoNdotU > 0.99) {
                                        float dFdxGLCA = dFdx(glColor.a);
                                        float dFdyGLCA = dFdy(glColor.a);

                                        if (abs(dFdxGLCA) + abs(dFdyGLCA) > 0.00001) {
                                            vec3 aoGradView = dFdxGLCA * normalize(dFdx(playerPos.xyz))
                                                            + dFdyGLCA * normalize(dFdy(playerPos.xyz));
                                            if (dot(normalize(aoGradView.xz), normalize(ViewToPlayer(lightVec).xz)) < 0.3 + 0.4 * dither)
                                                if (dot(lightVec, upVec) < 0.99999) centerFactor = sqrt1(max0(glColor.a - 0.55) / 0.45);
                                        }
                                    }
                                #endif

                                playerPosM = mix(playerPosM, centerPlayerPos, 0.2 * (1.0 - pow2(pow2(centerFactor))));
                            }
                        #elif defined GBUFFERS_HAND
                            playerPosM = mix(vec3(0.0), playerPosM, 0.2 + 0.8 * lightmapYM);
                        #elif defined GBUFFERS_TEXTURED
                            playerPosM = mix(centerPlayerPos, playerPosM + vec3(0.0, 0.02, 0.0), lightmapYM);
                        #else
                            playerPosM = mix(playerPosM, centerPlayerPos, 0.2 * (1.0 - lightmapYM));
                        #endif

                        // Shadow bias without peter-panning //
                        #ifndef GBUFFERS_TEXTURED
                            #ifdef GBUFFERS_TERRAIN
                                if (subsurfaceMode != 1)
                            #endif
                            {
                                float distanceBias = pow(dot(playerPos, playerPos), 0.75);
                                distanceBias = 0.12 + 0.0008 * distanceBias;
                                vec3 bias = worldGeoNormal * distanceBias * (2.0 - 0.95 * NdotLmax0); // 0.95 fixes pink petals noon shadows

                                #if defined GBUFFERS_TERRAIN && !defined DH_TERRAIN
                                    if (subsurfaceMode == 2) {
                                        bias *= vec3(0.0, 0.0, -0.5);
                                        bias.z += 0.25 * signMidCoordPos.x * NdotE;
                                    }
                                #endif

                                playerPosM += bias;
                            }
                        #endif

                        vec3 shadowPos = GetShadowPos(playerPosM);

                        bool leaves = false;
                        #ifdef GBUFFERS_TERRAIN
                            if (subsurfaceMode == 0) {
                                #if defined PERPENDICULAR_TWEAKS && defined SIDE_SHADOWING
                                    offset *= 1.0 + pow2(absNdotN);
                                #endif
                            } else {
                                float VdotL = dot(nViewPos, lightVec);
                                float lightFactor = pow(max(VdotL, 0.0), 10.0) * float(isEyeInWater == 0);
                                if (subsurfaceMode == 1) {
                                    offset = 0.0005235 * lightmapYM + 0.0009765;
                                    shadowPos.z -= max(NdotL * 0.0001, 0.0) * lightmapYM;
                                    subsurfaceHighlight = lightFactor * 0.8;
                                    #ifndef SHADOW_FILTERING
                                        shadowPos.z -= 0.0002;
                                    #endif
                                } else if (subsurfaceMode == 2) {
                                    leaves = true;
                                    offset = 0.0005235 * lightmapYM + 0.0009765;
                                    shadowPos.z -= 0.000175 * lightmapYM;
                                    subsurfaceHighlight = lightFactor * 0.6;
                                    #ifndef SHADOW_FILTERING
                                        NdotLM = mix(NdotL, NdotLM, 0.5);
                                    #endif
                                } else {
                                    
                                }
                            }
                        #endif
                        
                        int shadowSampleBooster = int(subsurfaceMode > 0 && lViewPos < 10.0);
                        #if SHADOW_QUALITY == 0
                            int shadowSamples = 0; // We don't use SampleTAAFilteredShadow on Shadow Quality 0
                        #elif SHADOW_QUALITY == 1
                            int shadowSamples = 1 + shadowSampleBooster;
                        #elif SHADOW_QUALITY == 2 || SHADOW_QUALITY == 3
                            int shadowSamples = 2 + 2 * shadowSampleBooster;
                        #elif SHADOW_QUALITY == 4
                            int shadowSamples = 4 + 4 * shadowSampleBooster;
                        #elif SHADOW_QUALITY == 5
                            int shadowSamples = 8 + 8 * shadowSampleBooster;
                        #endif

                        shadowMult *= GetShadow(shadowPos, lightmap.y, offset, shadowSamples, leaves);
                    }

                    float shadowSmooth = 16.0;
                    if (shadowLength < shadowSmooth) {
                        float shadowMixer = max0(shadowLength / shadowSmooth);

                        #ifdef GBUFFERS_TERRAIN
                            if (subsurfaceMode != 0) {
                                float shadowMixerM = pow2(shadowMixer);

                                if (subsurfaceMode == 1) skyLightShadowMult *= mix(0.6 + 0.3 * pow2(noonFactor), 1.0, shadowMixerM);
                                else skyLightShadowMult *= mix(NdotL * 0.4999 + 0.5, 1.0, shadowMixerM);

                                subsurfaceHighlight *= shadowMixer;
                            }
                        #endif

                        shadowMult = mix(vec3(skyLightShadowMult * shadowMultBeforeLighting), shadowMult, shadowMixer);
                    }
                }
            #else
                shadowMult *= skyLightShadowMult;
            #endif

            #ifdef CLOUD_SHADOWS
                shadowMult *= GetCloudShadow(playerPos);
            #endif

            // Cell Lighting: quantize NdotLM (the geometric diffuse factor) into
            // discrete bands before it is folded into shadowMult. This is the
            // correct insertion point: all NdotLM special cases (subsurface,
            // SIDE_SHADOWING, entity adjustments) are already resolved, and the
            // shadow map has already been sampled. Each surface face gets a flat
            // tonal value based on its angle to the sun -- the cel-shading effect.
            #if defined CELL_LIGHTING && SHADOW_QUALITY > -1
                // Shadow hardening: tighten the soft penumbra into a crisper step.
                // smoothstep window of 0.15 is narrow enough to read as hard-edged
                // while wide enough to remain TAA-stable in motion.
                float cellShadowLum = GetLuminance(shadowMult);
                if (cellShadowLum > 0.001 && cellShadowLum < 0.999) {
                    float cellShadowHard = smoothstep(0.35, 0.65, cellShadowLum);
                    shadowMult = (shadowMult / cellShadowLum) * cellShadowHard;
                }
            #endif
            #ifdef CELL_LIGHTING
                NdotLM = CellQuantize(NdotLM);
            #endif
            shadowMult *= max(NdotLM * shadowTime, 0.0);
        }
        #ifdef GBUFFERS_WATER
            else { // Low Quality Water
                shadowMult = vec3(pow2(lightmapY2) * max(NdotLM * shadowTime, 0.0));
            }
        #endif
    #endif

    // Blocklight
    float lightmapXM;
    if (!noSmoothLighting) {
        float lightmapXMSteep = pow2(pow2(lightmap.x * lightmap.x))  * (2.8 - 0.6 * vsBrightness + XLIGHT_CURVE);
        float lightmapXMCalm = (lightmap.x) * (2.8 + 0.6 * vsBrightness - XLIGHT_CURVE);
        lightmapXM = pow(lightmapXMSteep + lightmapXMCalm, 2.25);
    } else {
        float xLightCurveM = XLIGHT_CURVE > 0.999 ? XLIGHT_CURVE : sqrt2(XLIGHT_CURVE);
        lightmapXM = pow(lightmap.x, 3.0 * xLightCurveM) * 10.0;
    }

    float daylightFactor = lightmapYM * invRainFactor * sunVisibility;
    emission *= 1.0 - 0.25 * daylightFactor; // Less emission under direct skylight

    #ifdef GBUFFERS_TEXTURED
        lightmapXM *= 1.5 - 0.5 * daylightFactor; // Brighter lit particles
    #endif

    #if BLOCKLIGHT_FLICKERING > 0
        vec2 flickerNoise = texture2DLod(noisetex, vec2(frameTimeCounter * 0.06), 0.0).rb;
        lightmapXM *= mix(1.0, min1(max(flickerNoise.r, flickerNoise.g) * 1.7), pow2(BLOCKLIGHT_FLICKERING * 0.1));
    #endif

    // Cell Lighting blocklight quantization.
    // We use lightmap.x (0-1) to determine which brightness band we are in,
    // then multiply lightmapXM by (quantized_x / original_x). This keeps
    // lightmapXM in its normal range while stepping the falloff curve, since
    // the ratio is always safe (never multiplies by more than ~1.7x).
    #if defined CELL_LIGHTING && defined CELL_LIGHTING_BLOCKLIGHT
        if (lightmap.x > 0.001) {
            lightmapXM *= CellQuantizeBlocklight(lightmap.x) / lightmap.x;
        }
    #endif
    vec3 blockLighting = lightmapXM * blocklightCol;

    #if COLORED_LIGHTING_INTERNAL > 0
        // Prepare
        #if defined GBUFFERS_HAND
            vec3 voxelPos = SceneToVoxel(vec3(0.0));
        #elif defined GBUFFERS_TEXTURED
            vec3 voxelPos = SceneToVoxel(playerPos);
        #else
            vec3 voxelPos = SceneToVoxel(playerPos);
            voxelPos = voxelPos + worldGeoNormal * 0.55; // should be close to 0.5 for ACT_CORNER_LEAK_FIX but 0.5 makes slabs flicker
        #endif

        vec3 specialLighting = vec3(0.0);
        vec4 lightVolume = vec4(0.0);
        if (CheckInsideVoxelVolume(voxelPos)) {
            vec3 voxelPosM = clamp01(voxelPos / vec3(voxelVolumeSize));
            lightVolume = GetLightVolume(voxelPosM);
            lightVolume = sqrt(lightVolume);
            specialLighting = lightVolume.rgb;
        }

        // Add extra articial light for blocks that request it
        lightmapXM = max(lightmapXM, mix(lightmapXM, 10.0, lightVolume.a));
        specialLighting *= 1.0 + 50.0 * lightVolume.a;

        // Color Balance
        specialLighting = lightmapXM * 0.13 * DoLuminanceCorrection(specialLighting + blocklightCol * 0.05);

        // Add some extra non-contrasty detail
        AddSpecialLightDetail(specialLighting, color.rgb, emission);

        #if COLORED_LIGHT_SATURATION != 100
            specialLighting = mix(blockLighting, specialLighting, COLORED_LIGHT_SATURATION * 0.01);
        #endif

        // Serve with distance fade
        vec3 absPlayerPosM = abs(playerPos);
        #if COLORED_LIGHTING_INTERNAL <= 512
            absPlayerPosM.y *= 2.0;
        #elif COLORED_LIGHTING_INTERNAL == 768
            absPlayerPosM.y *= 3.0;
        #elif COLORED_LIGHTING_INTERNAL == 1024
            absPlayerPosM.y *= 4.0;
        #endif
        float maxPlayerPos = max(absPlayerPosM.x, max(absPlayerPosM.y, absPlayerPosM.z));
        float blocklightDecider = pow2(min1(maxPlayerPos / effectiveACTdistance * 2.0));
        //if (heldItemId != 40000 || heldItemId2 == 40000) // Hold spider eye to see vanilla lighting
        blockLighting = mix(specialLighting, blockLighting, blocklightDecider);
        //if (heldItemId2 == 40000 && heldItemId != 40000) blockLighting = lightVolume.rgb; // Hold spider eye to see light volume
    #endif

    #if HELD_LIGHTING_MODE >= 1
        #if !defined DO_PIXELATION_EFFECTS || !defined PIXELATED_BLOCKLIGHT
            vec3 playerPosForHeldLighting = playerPos;
        #else
            vec3 playerPosForHeldLighting = playerPosPixelated;
        #endif

        vec3 heldLighting = GetHeldLighting(playerPosForHeldLighting, color.rgb, emission);
        heldLighting *= HELD_LIGHTING_I;

        #ifdef GBUFFERS_HAND
            blockLighting *= 0.5;
            heldLighting *= 2.0;
        #endif
    #endif

    vec3 minLighting = GetMinimumLighting(lightmapYM);
    vec3 shadowLightMult = shadowMult;
    float shadowMultFloat = min1(GetLuminance(shadowMult));

    // Lighting Tweaks
    #ifdef OVERWORLD
        // Per-slider blend between rain and storm values based on thunderStrength.
        // At thunderFactor=0 pure rain settings apply; at 1.0 pure storm settings.
        float thunderFactor = GetThunderFactor();

        // Time-of-day weighted ambient level — blended between rain and storm.
        float rainTimedAL = mix(RAIN_NIGHT_AMBIENT_LEVEL,  mix(RAIN_DUSK_AMBIENT_LEVEL,  RAIN_DAY_AMBIENT_LEVEL,  noonFactor), sunVisibility2);
        float stormTimedAL = mix(STORM_NIGHT_AMBIENT_LEVEL, mix(STORM_DUSK_AMBIENT_LEVEL, STORM_DAY_AMBIENT_LEVEL, noonFactor), sunVisibility2);
        rainTimedAL = mix(rainTimedAL, stormTimedAL, thunderFactor);
        ambientMult = mix(lightmapYM, pow2(lightmapYM) * lightmapYM, rainFactor * rainTimedAL);

        #if SHADOW_QUALITY == -1
            float tweakFactor = 1.0 + 0.6 * (1.0 - pow2(pow2(pow2(noonFactor))));
            lightColorM /= tweakFactor;
            ambientMult *= mix(tweakFactor, 1.0, 0.5 * NdotUmax0);
        #endif

        #if AMBIENT_MULT != 100
            #if AMBIENT_MULT < 100
                #define AMBIENT_MULT_M (AMBIENT_MULT - 100) * 0.006
                vec3 shadowMultP = shadowMult / (0.1 + 0.9 * sqrt2(max0(NdotLM)));
                ambientMult *= 1.0 + pow2(pow2(max0(1.0 - dot(shadowMultP, shadowMultP)))) * AMBIENT_MULT_M *
                            (0.5 + 0.2 * sunFactor + 0.8 * noonFactor) * (1.0 - rainFactor * 0.5);
            #else
                #define AMBIENT_MULT_M (AMBIENT_MULT - 100) * 0.002
                shadowLightMult = mix(shadowLightMult, vec3(1.0), AMBIENT_MULT_M);
                lightColorM = mix(lightColorM, GetLuminance(lightColorM) * DoLuminanceCorrection(ambientColorM), (1.0 - shadowMultFloat) * AMBIENT_MULT_M);
            #endif
        #endif

        if (isEyeInWater != 1) {
            // Time-of-day weighted block light reach — blended between rain and storm.
            float rainTimedBL  = mix(RAIN_NIGHT_BLOCK_LIGHT,  mix(RAIN_DUSK_BLOCK_LIGHT,  RAIN_DAY_BLOCK_LIGHT,  noonFactor), sunVisibility2);
            float stormTimedBL = mix(STORM_NIGHT_BLOCK_LIGHT, mix(STORM_DUSK_BLOCK_LIGHT, STORM_DAY_BLOCK_LIGHT, noonFactor), sunVisibility2);
            float rainTimedBL_final = mix(rainTimedBL, stormTimedBL, thunderFactor);
            float lxFactor = (sunVisibility2 * 0.4 + (0.6 - 0.6 * pow2(invNoonFactor))) * (6.0 - 5.0 * rainFactor * rainTimedBL_final);
            lxFactor *= lightmapY2 + lightmapY2 * 2.0 * pow2(shadowMultFloat);
            lxFactor = max0(lxFactor - emission * 1000000.0);
            blockLighting *= pow(lightmapXM / 60.0 + 0.001, 0.09 * lxFactor);

            // Less light in the distance / more light closer to the camera during rain or night to simulate thicker fog
            // Time-of-day weighted light fog — blended between rain and storm.
            float rainLFBase   = mix(RAIN_NIGHT_LIGHT_FOG,  mix(RAIN_DUSK_LIGHT_FOG,  RAIN_DAY_LIGHT_FOG,  noonFactor), sunVisibility2);
            float stormLFBase  = mix(STORM_NIGHT_LIGHT_FOG, mix(STORM_DUSK_LIGHT_FOG, STORM_DAY_LIGHT_FOG, noonFactor), sunVisibility2);
            float rainTimedLF  = mix(rainLFBase, stormLFBase, thunderFactor);
            float rainLF = rainFactor * rainTimedLF;
            // Distance-based near/far contrast (atmospheric scattering simulation)
            float distFog = max0(96.0 - lViewPos) * (0.002 * (1.0 - sunVisibility2) + 0.001 * rainLF);
            // Global light reduction — 25% at full rain with slider at 1.0
            float globalDim = 0.25 * rainLF;
            float lightFogTweaks = max(0.5, 1.0 + distFog - globalDim);
            ambientMult *= lightFogTweaks;
            lightColorM *= lightFogTweaks;
        }
    #endif
    #ifdef END
        #if defined IS_IRIS && MC_VERSION >= 12109
            vec3 worldEndFlashPosition = mat3(gbufferModelViewInverse) * endFlashPosition;
            worldEndFlashPosition = normalize(vec3(worldEndFlashPosition.x, 0.0, worldEndFlashPosition.z));
            float endFlashDirectionFactor = max0(1.0 + dot(worldGeoNormal, normalize(worldEndFlashPosition))) * 0.5;
                  endFlashDirectionFactor = pow2(pow2(endFlashDirectionFactor));

            vec3 endFlashColor = (endOrangeCol + 0.5 * endLightColor) * endFlashIntensity * pow2(lightmapYM);
            ambientColorM += endFlashColor * (0.2 * endFlashDirectionFactor);
        #endif
    #endif

    #ifdef GBUFFERS_HAND
        ambientMult *= 1.3; // To improve held map visibility
    #endif

    // Directional Shading
    float directionShade = 1.0;
    #ifdef DIRECTIONAL_SHADING
        if (!noDirectionalShading) {
            float absNdotE2 = pow2(absNdotE);

            #if !defined NETHER
                float NdotUM = 0.75 + NdotU * 0.25;
            #else
                float NdotUM = 0.75 + abs(NdotU + 0.5) * 0.16666;
            #endif
            float NdotNM = 1.0 + 0.075 * absNdotN;
            float NdotEM = 1.0 - 0.1 * absNdotE2;
            directionShade = NdotUM * NdotEM * NdotNM;

            #ifdef OVERWORLD
                lightColorM *= 1.0 + absNdotE2 * 0.75;
            #elif defined NETHER
                directionShade *= directionShade;
                ambientColorM += lavaLightColor * pow2(absNdotN * 0.5 + max0(-NdotU)) * (0.7 + 0.35 * vsBrightness);
            #endif

            #if defined CUSTOM_PBR || defined GENERATED_NORMALS
                float cpbrAmbFactor = NdotN * NPdotU;
                cpbrAmbFactor = 1.0 - 0.3 * cpbrAmbFactor;
                ambientColorM *= cpbrAmbFactor;
                minLighting *= cpbrAmbFactor;
            #endif

            #if defined OVERWORLD && defined PERPENDICULAR_TWEAKS && defined SIDE_SHADOWING
                // Fake bounced light
                ambientColorM = mix(ambientColorM, lightColorM, (0.05 + 0.03 * subsurfaceMode) * absNdotN * lightmapY2);

                // Get a bit more natural looking lighting during noon
                lightColorM *= 1.0 + max0(1.0 - subsurfaceMode) * pow(noonFactor, 20.0) * (pow2(absNdotN) * 0.8 - absNdotE2 * 0.2);
            #endif
        }
    #endif

    // Scene Lighting Stuff
    // Cell Lighting: route ambient through CellAmbient() which applies the
    // selected ambient mode (Smooth / Reduced / Soft / Flat).
    #ifdef CELL_LIGHTING
        vec3 cellAmbientTerm = CellAmbient(ambientColorM * ambientMult);
        vec3 sceneLighting = lightColorM * shadowLightMult + cellAmbientTerm;
    #else
        vec3 sceneLighting = lightColorM * shadowLightMult + ambientColorM * ambientMult;
    #endif
    float dotSceneLighting = dot(sceneLighting, sceneLighting);

    #if HELD_LIGHTING_MODE >= 1
        blockLighting = sqrt(pow2(blockLighting) + heldLighting);
    #endif

    blockLighting *= XLIGHT_I;

    #ifdef LIGHT_COLOR_MULTS
        sceneLighting *= lightColorMult;
    #endif
    #ifdef MOON_PHASE_INF_LIGHT
        sceneLighting *= moonPhaseInfluence;
    #endif

    // Vanilla Ambient Occlusion
    float vanillaAO = 1.0;
    #if VANILLAAO_I > 0
        vanillaAO = glColor.a;

        #if defined DO_PIXELATION_EFFECTS && defined PIXELATED_AO
            vanillaAO = TexelSnap(vanillaAO, pixelationOffset);
        #endif

        if (subsurfaceMode != 0) vanillaAO = mix(min1(vanillaAO * 1.15), 1.0, shadowMultFloat);
        else if (!noVanillaAO) {
            #ifdef GBUFFERS_TERRAIN
                vanillaAO = min1(vanillaAO + 0.08);
                #ifdef OVERWORLD
                    vanillaAO = pow(
                        pow1_5(vanillaAO),
                        1.0 + dotSceneLighting * 0.02 + NdotUmax0 * (0.15 + 0.25 * pow2(noonFactor * pow2(lightmapY2)))
                    );
                #elif defined NETHER
                    vanillaAO = pow(
                        pow1_5(vanillaAO),
                        1.0 + NdotUmax0 * 0.5
                    );
                #else
                    vanillaAO = pow(
                        vanillaAO,
                        0.75 + NdotUmax0 * 0.25
                    );
                #endif
            #endif
            vanillaAO = vanillaAO * 0.9 + 0.1;

            #if VANILLAAO_I != 100
                #define VANILLAAO_IM VANILLAAO_I * 0.01
                vanillaAO = pow(vanillaAO, VANILLAAO_IM);
            #endif
        }
    #endif

    // Light Highlight
    vec3 lightHighlight = vec3(0.0);
    #ifdef LIGHT_HIGHLIGHT
        float specularHighlight = GGX(normalM, nViewPos, lightVec, NdotLmax0, smoothnessG);

        specularHighlight *= highlightMult;

        // Cell Lighting -- replace GGX with style-matched specular response.
        #ifdef CELL_LIGHTING
            specularHighlight = CellSpecular(specularHighlight);
        #endif

        lightHighlight = isEyeInWater != 1 ? shadowMult : pow(shadowMult, vec3(0.25)) * 0.35;
        lightHighlight *= (subsurfaceHighlight + specularHighlight) * highlightColor;

        #ifdef LIGHT_COLOR_MULTS
            lightHighlight *= lightColorMult;
        #endif
        #ifdef MOON_PHASE_INF_REFLECTION
            lightHighlight *= pow2(moonPhaseInfluence);
        #endif
    #endif

    // Mix Colors
    #ifdef CELL_LIGHTING
        float cellDirShade = mix(1.0, directionShade, CELL_DIRECTIONAL_SHADING_I);
    #else
        float cellDirShade = directionShade;
    #endif
    vec3 finalDiffuse = pow2(cellDirShade * vanillaAO) * (blockLighting + pow2(sceneLighting) + minLighting) + pow2(emission);
    finalDiffuse = sqrt(max(finalDiffuse, vec3(0.0))); // sqrt() for a bit more realistic light mix, max() to prevent NaNs

    // Apply Lighting
    color.rgb *= finalDiffuse;
    color.rgb += lightHighlight;
    color.rgb *= pow2(1.0 - darknessLightFactor);
}