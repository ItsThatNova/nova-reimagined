/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

// Weather-Reactive Surface Snow
// Applies shader-driven snow tinting to surfaces in snowy biomes,
// replacing the visual role of snow layer geometry (mat 10953).
// Snow layers are made invisible via the companion resource pack,
// and their break/drop behaviour is preserved by the game engine.
//
// When the Nova Reimagined Snow companion mod is installed, snow
// intensity is read from a per-chunk biome texture. The red channel
// encodes a continuous [0.0, 1.0] weight derived from biome temperature
// at terrain elevation, giving accurate biome boundaries and graduated
// coverage for transitional biomes at altitude.
//
// Without the companion mod installed, no snow draws on DH or regular terrain.

const float packSizeSLS = 16.0;

// Mod-provided textures registered via customTexture in shaders.properties.
uniform sampler2D snowBiomeMap;   // per-chunk eligibility: R=1.0 snow, R=0.0 no snow
uniform sampler2D snowBiomeMeta;  // 1x1: R=sizeEncoded, A=1.0 if mod active

// Snow surface texture variants — vanilla render path only.
// DH path uses procedural color since LOD geometry has no UVs.
uniform sampler2D snowTex1;
uniform sampler2D snowTex2;
uniform sampler2D snowTex3;
uniform sampler2D snowTex4;

/**
 * Samples the biome map for a world position with organic boundary blending.
 *
 * At chunk borders where a snowy chunk meets a non-snowy chunk, snow overdraws
 * into the non-snowy chunk following an organic noise-based boundary. Multi-octave
 * 2D noise warps the boundary into blob-like shapes, and the result is quantised
 * into discrete steps using the same technique as the sky-light snow gate, so the
 * boundary patches have the same stepped organic feel as snow under tree canopies.
 */
float sampleSnowBiome(vec3 playerPos) {
    vec4 meta = texelFetch(snowBiomeMeta, ivec2(0), 0);
    if (meta.a < 0.5) return 0.0;

    float size = pow(2.0, meta.r * 5.0 + 5.0);

    vec3 worldPos = playerPos + cameraPosition;

    ivec2 chunkCoord  = ivec2(floor(worldPos.xz / 16.0));
    ivec2 tc          = ivec2(mod(vec2(chunkCoord), size));
    float snowCurrent = texelFetch(snowBiomeMap, tc, 0).r;

    // Sample the 4 cardinal neighbours
    float snowPX = texelFetch(snowBiomeMap, ivec2(mod(vec2(chunkCoord + ivec2( 1, 0)), size)), 0).r;
    float snowNX = texelFetch(snowBiomeMap, ivec2(mod(vec2(chunkCoord + ivec2(-1, 0)), size)), 0).r;
    float snowPZ = texelFetch(snowBiomeMap, ivec2(mod(vec2(chunkCoord + ivec2( 0, 1)), size)), 0).r;
    float snowNZ = texelFetch(snowBiomeMap, ivec2(mod(vec2(chunkCoord + ivec2( 0,-1)), size)), 0).r;

    float maxNeighbour = max(max(snowPX, snowNX), max(snowPZ, snowNZ));
    if (maxNeighbour <= snowCurrent) return snowCurrent; // no snowy neighbours, skip

    // 2D multi-octave noise at the world position to form organic blob shapes.
    // Two octaves: coarse blobs at ~32-block scale, finer detail at ~16-block scale.
    vec2 noiseUV1 = worldPos.xz / 32.0;
    vec2 noiseUV2 = worldPos.xz / 16.0 + vec2(0.3, 0.7);
    float noise1 = texture2DLod(noisetex, noiseUV1, 0.0).r;
    float noise2 = texture2DLod(noisetex, noiseUV2, 0.0).r;
    float noise  = noise1 * 0.65 + noise2 * 0.35; // [0, 1], weighted blend

    // Max overdraw depth from any snowy neighbour, scaled by how much snowier it is.
    float snowDiff = maxNeighbour - snowCurrent;

    // Overdraw distance in chunk fractions: 4-10 blocks base + noise warp.
    // The noise shifts the effective boundary so blobs form naturally.
    float overdrawFrac = (4.0 + noise * 6.0) / 16.0;

    // Fractional distance to the nearest snowy neighbour edge, in [0, 1].
    // 0.0 = right at the border, 1.0 = far side of the chunk.
    vec2 chunkFrac = fract(worldPos.xz / 16.0);
    float distPX = 1.0 - chunkFrac.x; // distance to +X edge
    float distNX = chunkFrac.x;        // distance to -X edge
    float distPZ = 1.0 - chunkFrac.y; // distance to +Z edge
    float distNZ = chunkFrac.y;        // distance to -Z edge

    // For each edge with a snowy neighbour, compute proximity to that edge.
    // Only consider edges where the neighbour is actually snowier.
    float proximity = 0.0;
    if (snowPX > snowCurrent) proximity = max(proximity, (1.0 - distPX / overdrawFrac) * (snowPX - snowCurrent));
    if (snowNX > snowCurrent) proximity = max(proximity, (1.0 - distNX / overdrawFrac) * (snowNX - snowCurrent));
    if (snowPZ > snowCurrent) proximity = max(proximity, (1.0 - distPZ / overdrawFrac) * (snowPZ - snowCurrent));
    if (snowNZ > snowCurrent) proximity = max(proximity, (1.0 - distNZ / overdrawFrac) * (snowNZ - snowCurrent));

    proximity = clamp(proximity, 0.0, 1.0);

    // Quantise into discrete steps — same technique as the sky-light snow gate.
    // This gives the same stepped organic patches seen under tree canopies.
    #ifdef SNOW_PIXEL
        float steps   = float(SNOW_PIXEL_SIZE);
        proximity     = floor(proximity * steps) / steps;
    #else
        // Without SNOW_PIXEL, use 4 steps for a clean stepped look
        proximity     = floor(proximity * 4.0) / 4.0;
    #endif

    return min(1.0, snowCurrent + proximity);
}

void DoSurfaceSnow(inout vec4 color, inout float smoothnessG, inout float highlightMult,
                   inout float smoothnessD, inout float emission,
                   vec3 playerPos, vec2 lmCoord, float snowMinNdotU,
                   float NdotU, int subsurfaceMode, int mat) {

    bool applySnow = false;
    float intensity = 1.0;

    #ifdef LEAF_SNOW
        if (!applySnow && (mat == 10009
            #ifdef DH_TERRAIN
                || mat == DH_BLOCK_LEAVES
            #endif
        )) {
            applySnow = true;
            intensity = LEAF_SNOW_INTENSITY;
        }
    #endif

    #ifdef FOLIAGE_SNOW
        if (!applySnow && (
            mat == 10001 || mat == 10005 || mat == 10013 ||
            mat == 10017 || mat == 10021
            #ifdef DH_TERRAIN
                || mat == DH_BLOCK_GRASS
            #endif
        )) {
            applySnow = true;
            intensity = FOLIAGE_SNOW_INTENSITY;
        }
    #endif

    #ifdef TERRAIN_SNOW
        if (!applySnow && (
            mat == 10080 || mat == 10083 || mat == 10084 || mat == 10087 ||
            mat == 10088 || mat == 10091 || mat == 10092 || mat == 10095 ||
            mat == 10096 || mat == 10099 || mat == 10100 || mat == 10103 ||
            mat == 10104 || mat == 10107 || mat == 10108 || mat == 10111 ||
            mat == 10116 || mat == 10120 ||
            mat == 10124 || mat == 10128 || mat == 10129 || mat == 10132 ||
            mat == 10137 || mat == 10152 || mat == 10153 || mat == 10155 ||
            mat == 10228 || mat == 10232 || mat == 10236 || mat == 10372 ||
            mat == 10724 || mat == 10744
            #ifdef DH_TERRAIN
                || mat == DH_BLOCK_STONE || mat == DH_BLOCK_DIRT || mat == DH_BLOCK_SAND
            #endif
        )) {
            applySnow = true;
            intensity = TERRAIN_SNOW_INTENSITY;
        }
    #endif

    #ifdef WOOD_SNOW
        if (!applySnow && (
            mat == 10156 || mat == 10159 || mat == 10160 ||
            mat == 10164 || mat == 10167 || mat == 10168 ||
            mat == 10172 || mat == 10175 || mat == 10176 ||
            mat == 10180 || mat == 10183 || mat == 10184 ||
            mat == 10188 || mat == 10191 || mat == 10192 ||
            mat == 10196 || mat == 10199 || mat == 10200 ||
            mat == 10204 || mat == 10207 || mat == 10208 ||
            mat == 10212 || mat == 10215 || mat == 10216 ||
            mat == 10220 || mat == 10223 || mat == 10224 ||
            mat == 10756 || mat == 10759 || mat == 10760 ||
            mat == 10763 || mat == 10764 || mat == 10928 ||
            mat == 10931 || mat == 10932 ||
            // fences and fence gates (oak, spruce, birch, jungle, acacia, dark oak, mangrove, cherry)
            mat == 10157 || mat == 10165 || mat == 10173 ||
            mat == 10181 || mat == 10189 || mat == 10197 ||
            mat == 10205 || mat == 10761
            #ifdef DH_TERRAIN
                || mat == DH_BLOCK_WOOD
            #endif
        )) {
            applySnow = true;
            intensity = WOOD_SNOW_INTENSITY;
        }
    #endif

    #ifdef STRUCTURE_SNOW
        if (!applySnow && (
            mat == 10032 || mat == 10033 || mat == 10035 ||
            mat == 10240 || mat == 10243 || mat == 10244 ||
            mat == 10247 || mat == 10260 || mat == 10264 ||
            mat == 10292 || mat == 10364 || mat == 10367 ||
            mat == 10376 || mat == 10379 || mat == 10408 ||
            mat == 10416 || mat == 10419 || mat == 10420 ||
            mat == 10423 || mat == 10428 || mat == 10429 ||
            mat == 10431 || mat == 10432 || mat == 10436 ||
            mat == 10440 || mat == 10443 || mat == 10444 ||
            mat == 10447 || mat == 10460 || mat == 10464 ||
            mat == 10480 || mat == 10481 || mat == 10483 ||
            mat == 10668 || mat == 10669 || mat == 10676 ||
            mat == 10712 || mat == 10713 || mat == 10715 ||
            mat == 10888 || mat == 10924 ||
            mat == 5008  || mat == 5012  || // chests (vanilla + betternether)
            // deepslate processed/structural variants
            mat == 10109 || mat == 10112 || mat == 10113 || mat == 10115
            #ifdef DH_TERRAIN
                || mat == DH_BLOCK_METAL || mat == DH_BLOCK_TERRACOTTA
            #endif
        )) {
            applySnow = true;
            intensity = STRUCTURE_SNOW_INTENSITY;
        }
    #endif

    // Catch-all for DH terrain blocks that don't match any named material constant.
    // Cobbled deepslate, stairs, and other block types DH doesn't expose specifically
    // all fall through to here. Top-face snow only — sideFactor is already 0 for
    // non-leaves so this won't cause side-face over-coverage on structures.
    #ifdef DH_TERRAIN
        if (!applySnow && mat != DH_BLOCK_LAVA && mat != DH_BLOCK_ILLUMINATED) {
            applySnow = true;
            intensity = TERRAIN_SNOW_INTENSITY;
        }
    #endif

    // Path blocks (dirt_path and modded equivalents): snow draws only on the
    // outer edges, fading toward the centre with noise to simulate sun melt.
    // The same quantised step technique as the biome boundary and canopy fade
    // is used so the melt pattern looks consistent with the rest of the shader.
    #ifndef DH_TERRAIN
    if (!applySnow && mat == 10494) {
        applySnow = true;
        intensity = TERRAIN_SNOW_INTENSITY;

        // 2D noise at two scales — coarse for large melt patches, fine for texture.
        vec3 pathWorldPos = playerPos + cameraPosition;
        float pathNoise1  = texture2DLod(noisetex, pathWorldPos.xz / (20.0 * PATH_SNOW_PATCH_SCALE), 0.0).r;
        float pathNoise2  = texture2DLod(noisetex, pathWorldPos.xz / (8.0  * PATH_SNOW_PATCH_SCALE) + vec2(0.5, 0.2), 0.0).r;
        float pathNoise   = pathNoise1 * 0.6 + pathNoise2 * 0.4; // [0, 1]

        // Quantise into steps matching the canopy/boundary fade style.
        #ifdef SNOW_PIXEL
            float pathSteps = float(SNOW_PIXEL_SIZE);
            pathNoise = floor(pathNoise * pathSteps) / pathSteps;
        #else
            pathNoise = floor(pathNoise * 4.0) / 4.0;
        #endif

        // Scale snow intensity by the user-configured maximum coverage.
        intensity = TERRAIN_SNOW_INTENSITY * PATH_SNOW_MAX_COVERAGE;

        // If the path noise is essentially zero, skip drawing entirely.
        if (pathNoise <= 0.0) return;
    }
    #endif

    if (!applySnow) return;

    // Snow driver: mod texture for accurate per-chunk biome boundaries.
    // Returns 0.0 if mod not active, so no snow draws without the mod.
    float snowDriver = sampleSnowBiome(playerPos);

    // Flat snowMinNdotU for leaves so all leaf colours are treated equally
    float snowMinNdotULocal = snowMinNdotU;
    #if defined LEAF_SNOW || defined FOLIAGE_SNOW
        if (mat == 10009 || mat == 10005 || mat == 10021) {
            snowMinNdotULocal = 0.08;
        } else if (mat == 10001 || mat == 10013 || mat == 10017) {
            snowMinNdotULocal = 0.05;
        }
    #endif

    // World position needed before gate for pixel snapping
    vec3 worldPos = playerPos + cameraPosition;

    // Gate: upward-facing, sky-exposed, not near block light.
    // For DH LODs, skip the lmCoord.y sky-exposure gate entirely — LOD
    // geometry doesn't have accurate sky light values, so the 0.9 threshold
    // would cause the band/flickering issues. Just use NdotU and block light.
    // When SNOW_PIXEL is active, quantise lmCoord.y within its effective
    // range before the gate for a stepped pixel-locked look.
    #ifdef DH_TERRAIN
        // For LODs, upward faces get full snow coverage.
        // Side faces get noise-driven partial coverage so trees read as
        // snowy from eye level at distance rather than appearing snowless.
        // Downward faces (NdotU < -0.1) never get snow.
        // Side faces get a uniform contribution based purely on their angle —
        // no noise or stochastic component. This is completely stable as the
        // camera moves since both NdotU and snowDriver are constant per face.
        // Side-face snow is restricted to leaves only — trees need it to read
        // as snowy from eye level at distance. All other materials (stone, wood,
        // dirt, sand etc) only receive snow on top faces to avoid over-coverage
        // on structures and terrain.
        float upFactor   = max(NdotU, 0.0);
        float sideFactor = 0.0;
        if (mat == DH_BLOCK_LEAVES) {
            sideFactor = (NdotU >= -0.1 && NdotU < 0.5)
                       ? clamp(1.0 - abs(NdotU) * 2.0, 0.0, 1.0) * 0.6
                       : 0.0;
        }
        float snowFactorM = max(upFactor + sideFactor, 0.0);
    #else
        #ifdef SNOW_PIXEL
            float steps        = float(SNOW_PIXEL_SIZE);
            float skyNorm      = clamp((lmCoord.y - 0.9) / 0.1, 0.0, 1.0);
            float snowFactorM  = 1000.0
                               * max(NdotU - 0.9, snowMinNdotULocal)
                               * skyNorm * 0.1
                               * (0.9 - clamp(lmCoord.x, 0.8, 0.9));
            // Pixel-locked two-octave noise breaks the smooth gradient into
            // path-snow-style patches. snowFactorM still drives the fade,
            // canopyNoise just shapes which pixels within the fade zone draw.
            float canopyNoise1 = texture2DLod(noisetex, worldPos.xz / (20.0 * PATH_SNOW_PATCH_SCALE), 0.0).r;
            float canopyNoise2 = texture2DLod(noisetex, worldPos.xz / (8.0  * PATH_SNOW_PATCH_SCALE) + vec2(0.5, 0.2), 0.0).r;
            float canopyNoise  = floor((canopyNoise1 * 0.6 + canopyNoise2 * 0.4) * steps) / steps;
            snowFactorM *= canopyNoise;
        #else
            float snowFactorM  = 1000.0
                               * max(NdotU - 0.9, snowMinNdotULocal)
                               * max0(lmCoord.y - 0.9)
                               * (0.9 - clamp(lmCoord.x, 0.8, 0.9));
        #endif
    #endif

    if (snowFactorM <= 0.0001) return;

    // snowDriver is now a continuous intensity in [0.0, 1.0] derived from biome
    // temperature at terrain elevation. 1.0 = fully snowy biome (snowy plains,
    // frozen peaks), lower values for transitional biomes at altitude (taiga
    // near its snow line, windswept hills). Applying it after the geometry clamp
    // means the per-surface intensity sliders still set the visual ceiling, and
    // snowDriver scales downward from that ceiling for partial-snow situations.
    snowFactorM = clamp(snowFactorM * intensity, 0.0, 1.0) * snowDriver;
    if (snowFactorM <= 0.0001) return;

    // Snow color and surface texture.
    // DH path: snap noise coord to block grid to reduce flicker, use procedural color.
    // Vanilla path: hash world block position to select one of 4 snow texture variants,
    //   tile the selected texture across the surface for the snow color.
    // When SNOW_PIXEL is active, snap XZ to cell grid so noise has hard edges.
    #if defined DH_TERRAIN
        vec2 noiseCoord  = floor(worldPos.xz + 0.5) / packSizeSLS;
             noiseCoord += floor(packSizeSLS * worldPos.y + 0.001) / packSizeSLS;
        float noiseTexture = dot(vec2(0.25, 0.75),
                                 texture2DLod(noisetex, noiseCoord * 0.45, 0.0).rg);
        vec3 snowColor = vec3(1.0);
    #else
        #ifdef SNOW_PIXEL
            float pixelGrid2 = float(SNOW_PIXEL_SIZE);
            vec2  snappedXZ  = floor(worldPos.xz / pixelGrid2) * pixelGrid2;
            vec2 noiseCoord  = floor(packSizeSLS * snappedXZ  + 0.001) / packSizeSLS;
                 noiseCoord += floor(packSizeSLS * worldPos.y + 0.001) / packSizeSLS;
        #else
            vec2 noiseCoord  = floor(packSizeSLS * worldPos.xz + 0.001) / packSizeSLS;
                 noiseCoord += floor(packSizeSLS * worldPos.y  + 0.001) / packSizeSLS;
        #endif
        float noiseTexture = dot(vec2(0.25, 0.75),
                                 texture2DLod(noisetex, noiseCoord * 0.45, 0.0).rg);

        // Hash the integer block position to pick one of 4 snow texture variants.
        // floor before hash so all fragments on the same block get the same texture.
        vec3  blockPos  = floor(worldPos + 0.5);
        float blockHash = fract(sin(dot(blockPos, vec3(127.1, 311.7, 74.7))) * 43758.5453);
        // Tile UVs across the surface at 1 texture per 2 blocks
        vec2  snowUV    = fract(worldPos.xz * 0.5 + 0.5);
        vec3 snowTexColor;
        if      (blockHash < 0.25) snowTexColor = texture2D(snowTex1, snowUV).rgb;
        else if (blockHash < 0.50) snowTexColor = texture2D(snowTex2, snowUV).rgb;
        else if (blockHash < 0.75) snowTexColor = texture2D(snowTex3, snowUV).rgb;
        else                       snowTexColor = texture2D(snowTex4, snowUV).rgb;
        vec3 snowColor = snowTexColor;
    #endif

    #ifdef DH_TERRAIN
        // Neutralize the base color toward greyscale before mixing snow to prevent
        // biome grass/dirt tint (greenish-blue in cold biomes) from bleeding through.
        float baseLuma   = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        vec3 baseNeutral = vec3(0.98, 0.97, 0.96);
        color.rgb = mix(baseNeutral, snowColor + baseNeutral * emission * 0.2, snowFactorM);
    #else
        color.rgb = mix(color.rgb, snowColor + color.rgb * emission * 0.2, snowFactorM);
    #endif
    smoothnessG   = mix(smoothnessG,   0.25 + 0.25 * noiseTexture,         snowFactorM);
    highlightMult = mix(highlightMult, 2.0 - subsurfaceMode * 0.666,        snowFactorM);
    smoothnessD   = mix(smoothnessD,   0.0,                                 snowFactorM);
    emission     *= 1.0 - snowFactorM * 0.85;
}