/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

// SMAA 1x Ultra Quality
// Enhanced Subpixel Morphological Antialiasing
// Based on the reference implementation by Jorge Jimenez et al.
// https://github.com/iryoku/smaa
// MIT License — copyright notice preserved as required.
//
// Copyright (C) 2013 Jorge Jimenez (jorge@iryoku.com)
// Copyright (C) 2013 Jose I. Echevarria (joseignacioechevarria@gmail.com)
// Copyright (C) 2013 Belen Masia (bmasia@unizar.es)
// Copyright (C) 2013 Fernando Navarro (fernandn@microsoft.com)
// Copyright (C) 2013 Diego Gutierrez (diegog@unizar.es)
//
// Ported to GLSL for Iris/Optifine shader pipeline.
// Input: gamma-corrected color in colortex3 (post-TAA, post-LinearToRGB).
// Pass 1 (composite8): Luma edge detection    -> colortex9  (RG8)
// Pass 2 (composite9): Blending weight calc   -> colortex10 (RGBA8)
// Pass 3 (composite10): Neighbourhood blend   -> colortex3  (final output)

// --- Target and preset ---
#define SMAA_GLSL_3
#define SMAA_PRESET_ULTRA
// SMAA_PRESET_ULTRA sets:
//   SMAA_THRESHOLD              0.05
//   SMAA_MAX_SEARCH_STEPS       32
//   SMAA_MAX_SEARCH_STEPS_DIAG  16
//   SMAA_CORNER_ROUNDING        25

// --- Runtime metrics (set per-pass before including this file) ---
// #define SMAA_RT_METRICS vec4(1.0/viewWidth, 1.0/viewHeight, viewWidth, viewHeight)

// --- Texture channel selectors ---
// AreaTexDX10.png stores data in RG channels
#define SMAA_AREATEX_SELECT(s)   s.rg
// SearchTex.png stores data in R channel
#define SMAA_SEARCHTEX_SELECT(s) s.r

// --- Preset defines ---
#if defined(SMAA_PRESET_LOW)
    #define SMAA_THRESHOLD 0.15
    #define SMAA_MAX_SEARCH_STEPS 4
    #define SMAA_DISABLE_DIAG_DETECTION
    #define SMAA_DISABLE_CORNER_DETECTION
#elif defined(SMAA_PRESET_MEDIUM)
    #define SMAA_THRESHOLD 0.1
    #define SMAA_MAX_SEARCH_STEPS 8
    #define SMAA_DISABLE_DIAG_DETECTION
    #define SMAA_DISABLE_CORNER_DETECTION
#elif defined(SMAA_PRESET_HIGH)
    #define SMAA_THRESHOLD 0.1
    #define SMAA_MAX_SEARCH_STEPS 16
    #define SMAA_MAX_SEARCH_STEPS_DIAG 8
    #define SMAA_CORNER_ROUNDING 25
#elif defined(SMAA_PRESET_ULTRA)
    #define SMAA_THRESHOLD 0.05
    #define SMAA_MAX_SEARCH_STEPS 32
    #define SMAA_MAX_SEARCH_STEPS_DIAG 16
    #define SMAA_CORNER_ROUNDING 25
#endif

// --- Configurable defaults (if not set by preset) ---
#ifndef SMAA_THRESHOLD
    #define SMAA_THRESHOLD 0.1
#endif
#ifndef SMAA_DEPTH_THRESHOLD
    #define SMAA_DEPTH_THRESHOLD (0.1 * SMAA_THRESHOLD)
#endif
#ifndef SMAA_MAX_SEARCH_STEPS
    #define SMAA_MAX_SEARCH_STEPS 16
#endif
#ifndef SMAA_MAX_SEARCH_STEPS_DIAG
    #define SMAA_MAX_SEARCH_STEPS_DIAG 8
#endif
#ifndef SMAA_CORNER_ROUNDING
    #define SMAA_CORNER_ROUNDING 25
#endif
#ifndef SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR
    #define SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR 2.0
#endif
#ifndef SMAA_PREDICATION
    #define SMAA_PREDICATION 1
#endif
#ifndef SMAA_PREDICATION_THRESHOLD
    // Depth difference that triggers predication assistance.
    // 0.01 catches most geometry edges without false positives on flat surfaces.
    #define SMAA_PREDICATION_THRESHOLD 0.01
#endif
#ifndef SMAA_PREDICATION_SCALE
    // How aggressively predication lowers the luma threshold at depth edges.
    // 2.0 = threshold halved at confirmed depth edges.
    #define SMAA_PREDICATION_SCALE 2.0
#endif
#ifndef SMAA_PREDICATION_STRENGTH
    // Blend between predication-modulated and flat threshold. 0.4 is conservative.
    #define SMAA_PREDICATION_STRENGTH 0.4
#endif

// --- Non-configurable constants ---
#define SMAA_AREATEX_MAX_DISTANCE     16
#define SMAA_AREATEX_MAX_DISTANCE_DIAG 20
#define SMAA_AREATEX_PIXEL_SIZE       (1.0 / vec2(160.0, 560.0))
#define SMAA_AREATEX_SUBTEX_SIZE      (1.0 / 7.0)
#define SMAA_SEARCHTEX_SIZE           vec2(66.0, 33.0)
#define SMAA_SEARCHTEX_PACKED_SIZE    vec2(64.0, 16.0)
#define SMAA_CORNER_ROUNDING_NORM     (float(SMAA_CORNER_ROUNDING) / 100.0)

// --- GLSL porting macros ---
#define SMAATexture2D(tex)                          sampler2D tex
#define SMAATexturePass2D(tex)                      tex
#define SMAASampleLevelZero(tex, coord)             textureLod(tex, coord, 0.0)
#define SMAASampleLevelZeroPoint(tex, coord)        textureLod(tex, coord, 0.0)
#define SMAASampleLevelZeroOffset(tex, coord, off)  textureLodOffset(tex, coord, 0.0, off)
#define SMAASample(tex, coord)                      texture2D(tex, coord)
#define SMAASamplePoint(tex, coord)                 texture2D(tex, coord)
#define SMAASampleOffset(tex, coord, off)           texture2D(tex, coord + vec2(off) * SMAA_RT_METRICS.xy)
#define SMAA_FLATTEN
#define SMAA_BRANCH
#define mad(a, b, c)                                (a * b + c)
#define saturate(a)                                 clamp(a, 0.0, 1.0)

// --- Conditional move helpers ---
void SMAAMovc(bvec2 cond, inout vec2 variable, vec2 value) {
    SMAA_FLATTEN if (cond.x) variable.x = value.x;
    SMAA_FLATTEN if (cond.y) variable.y = value.y;
}
void SMAAMovc(bvec4 cond, inout vec4 variable, vec4 value) {
    SMAAMovc(cond.xy, variable.xy, value.xy);
    SMAAMovc(cond.zw, variable.zw, value.zw);
}

// =============================================================================
// VERTEX SHADER OFFSET FUNCTIONS
// Call these in the vertex shader of each pass to precompute UV offsets.
// =============================================================================

void SMAAEdgeDetectionVS(vec2 texcoord, out vec4 offset[3]) {
    offset[0] = mad(SMAA_RT_METRICS.xyxy, vec4(-1.0,  0.0,  0.0, -1.0), texcoord.xyxy);
    offset[1] = mad(SMAA_RT_METRICS.xyxy, vec4( 1.0,  0.0,  0.0,  1.0), texcoord.xyxy);
    offset[2] = mad(SMAA_RT_METRICS.xyxy, vec4(-2.0,  0.0,  0.0, -2.0), texcoord.xyxy);
}

void SMAABlendingWeightCalculationVS(vec2 texcoord, out vec2 pixcoord, out vec4 offset[3]) {
    pixcoord = texcoord * SMAA_RT_METRICS.zw;
    offset[0] = mad(SMAA_RT_METRICS.xyxy, vec4(-0.25, -0.125,  1.25, -0.125), texcoord.xyxy);
    offset[1] = mad(SMAA_RT_METRICS.xyxy, vec4(-0.125, -0.25, -0.125,  1.25), texcoord.xyxy);
    offset[2] = mad(SMAA_RT_METRICS.xxyy,
                    vec4(-2.0, 2.0, -2.0, 2.0) * float(SMAA_MAX_SEARCH_STEPS),
                    vec4(offset[0].xz, offset[1].yw));
}

void SMAANeighborhoodBlendingVS(vec2 texcoord, out vec4 offset) {
    offset = mad(SMAA_RT_METRICS.xyxy, vec4(1.0, 0.0, 0.0, 1.0), texcoord.xyxy);
}

// =============================================================================
// PREDICATION
// Uses depth discontinuities to modulate the luma edge threshold.
// At geometry edges confirmed by depth, the threshold is lowered so SMAA
// catches fine edges that luma alone might miss (e.g. low-contrast geometry).
// =============================================================================

#if SMAA_PREDICATION == 1
vec2 SMAAPredicatedThreshold(vec2 texcoord, vec4 offset[3], sampler2D predicationTex) {
    float here  = textureLod(predicationTex, texcoord,     0.0).r;
    float left  = textureLod(predicationTex, offset[0].xy, 0.0).r;
    float top   = textureLod(predicationTex, offset[0].zw, 0.0).r;
    vec2 pred   = abs(vec2(here) - vec2(left, top));
    vec2 edges  = step(vec2(SMAA_PREDICATION_THRESHOLD), pred);
    return SMAA_THRESHOLD * (1.0 - SMAA_PREDICATION_STRENGTH * edges / SMAA_PREDICATION_SCALE);
}
#endif

// =============================================================================
// PASS 1 — LUMA EDGE DETECTION
// Input:  colorTex (gamma-corrected color, colortex3)
// Output: vec2 edges written to colortex9 RG channels
// Uses Rec.709 luma weights — consistent with our other AA work.
// =============================================================================

vec2 SMAALumaEdgeDetectionPS(vec2 texcoord, vec4 offset[3], SMAATexture2D(colorTex)
    #if SMAA_PREDICATION == 1
    , sampler2D predicationTex
    #endif
) {
    #if SMAA_PREDICATION == 1
    vec2 threshold = SMAAPredicatedThreshold(texcoord, offset, predicationTex);
    #else
    vec2 threshold = vec2(SMAA_THRESHOLD, SMAA_THRESHOLD);
    #endif

    // Rec.709 luma weights
    vec3 weights = vec3(0.2126, 0.7152, 0.0722);

    float L      = dot(SMAASamplePoint(colorTex, texcoord).rgb,    weights);
    float Lleft  = dot(SMAASamplePoint(colorTex, offset[0].xy).rgb, weights);
    float Ltop   = dot(SMAASamplePoint(colorTex, offset[0].zw).rgb, weights);

    vec4 delta;
    delta.xy = abs(L - vec2(Lleft, Ltop));
    vec2 edges = step(threshold, delta.xy);

    if (dot(edges, vec2(1.0, 1.0)) == 0.0)
        discard;

    float Lright  = dot(SMAASamplePoint(colorTex, offset[1].xy).rgb, weights);
    float Lbottom = dot(SMAASamplePoint(colorTex, offset[1].zw).rgb, weights);
    delta.zw = abs(L - vec2(Lright, Lbottom));

    vec2 maxDelta = max(delta.xy, delta.zw);

    float Lleftleft = dot(SMAASamplePoint(colorTex, offset[2].xy).rgb, weights);
    float Ltoptop   = dot(SMAASamplePoint(colorTex, offset[2].zw).rgb, weights);
    delta.zw = abs(vec2(Lleft, Ltop) - vec2(Lleftleft, Ltoptop));

    maxDelta = max(maxDelta.xy, delta.zw);
    float finalDelta = max(maxDelta.x, maxDelta.y);

    edges.xy *= step(finalDelta, SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR * delta.xy);

    return edges;
}

// =============================================================================
// PASS 2 — BLENDING WEIGHT CALCULATION
// Helper functions
// =============================================================================

// Diagonal bilinear decode
vec2 SMAADecodeDiagBilinearAccess(vec2 e) {
    e.r = e.r * abs(5.0 * e.r - 5.0 * 0.75);
    return round(e);
}
vec4 SMAADecodeDiagBilinearAccess(vec4 e) {
    e.rb = e.rb * abs(5.0 * e.rb - 5.0 * 0.75);
    return round(e);
}

// Diagonal searches
vec2 SMAASearchDiag1(SMAATexture2D(edgesTex), vec2 texcoord, vec2 dir, out vec2 e) {
    vec4 coord = vec4(texcoord, -1.0, 1.0);
    vec3 t = vec3(SMAA_RT_METRICS.xy, 1.0);
    for (int i = 0; i < SMAA_MAX_SEARCH_STEPS_DIAG; i++) {
        if (!(coord.z < float(SMAA_MAX_SEARCH_STEPS_DIAG - 1) && coord.w > 0.9)) break;
        coord.xyz = mad(t, vec3(dir, 1.0), coord.xyz);
        e = SMAASampleLevelZero(edgesTex, coord.xy).rg;
        coord.w = dot(e, vec2(0.5, 0.5));
    }
    return coord.zw;
}

vec2 SMAASearchDiag2(SMAATexture2D(edgesTex), vec2 texcoord, vec2 dir, out vec2 e) {
    vec4 coord = vec4(texcoord, -1.0, 1.0);
    coord.x += 0.25 * SMAA_RT_METRICS.x;
    vec3 t = vec3(SMAA_RT_METRICS.xy, 1.0);
    for (int i = 0; i < SMAA_MAX_SEARCH_STEPS_DIAG; i++) {
        if (!(coord.z < float(SMAA_MAX_SEARCH_STEPS_DIAG - 1) && coord.w > 0.9)) break;
        coord.xyz = mad(t, vec3(dir, 1.0), coord.xyz);
        e = SMAASampleLevelZero(edgesTex, coord.xy).rg;
        e = SMAADecodeDiagBilinearAccess(e);
        coord.w = dot(e, vec2(0.5, 0.5));
    }
    return coord.zw;
}

vec2 SMAAAreaDiag(SMAATexture2D(areaTex), vec2 dist, vec2 e, float offset) {
    vec2 texcoord = mad(vec2(SMAA_AREATEX_MAX_DISTANCE_DIAG, SMAA_AREATEX_MAX_DISTANCE_DIAG), e, dist);
    texcoord = mad(SMAA_AREATEX_PIXEL_SIZE, texcoord, 0.5 * SMAA_AREATEX_PIXEL_SIZE);
    texcoord.x += 0.5;
    texcoord.y += SMAA_AREATEX_SUBTEX_SIZE * offset;
    return SMAA_AREATEX_SELECT(SMAASampleLevelZero(areaTex, texcoord));
}

vec2 SMAACalculateDiagWeights(SMAATexture2D(edgesTex), SMAATexture2D(areaTex),
                               vec2 texcoord, vec2 e, vec4 subsampleIndices) {
    vec2 weights = vec2(0.0);
    vec4 d;
    vec2 end;

    if (e.r > 0.0) {
        d.xz = SMAASearchDiag1(SMAATexturePass2D(edgesTex), texcoord, vec2(-1.0, 1.0), end);
        d.x += float(end.y > 0.9);
    } else {
        d.xz = vec2(0.0);
    }
    d.yw = SMAASearchDiag1(SMAATexturePass2D(edgesTex), texcoord, vec2(1.0, -1.0), end);

    SMAA_BRANCH
    if (d.x + d.y > 2.0) {
        vec4 coords = mad(vec4(-d.x + 0.25, d.x, d.y, -d.y - 0.25), SMAA_RT_METRICS.xyxy, texcoord.xyxy);
        vec4 c;
        c.xy = SMAASampleLevelZeroOffset(edgesTex, coords.xy, ivec2(-1,  0)).rg;
        c.zw = SMAASampleLevelZeroOffset(edgesTex, coords.zw, ivec2( 1,  0)).rg;
        c.yxwz = SMAADecodeDiagBilinearAccess(c.xyzw);
        vec2 cc = mad(vec2(2.0), c.xz, c.yw);
        SMAAMovc(bvec2(step(0.9, d.zw)), cc, vec2(0.0));
        weights += SMAAAreaDiag(SMAATexturePass2D(areaTex), d.xy, cc, subsampleIndices.z);
    }

    d.xz = SMAASearchDiag2(SMAATexturePass2D(edgesTex), texcoord, vec2(-1.0, -1.0), end);
    if (SMAASampleLevelZeroOffset(edgesTex, texcoord, ivec2(1, 0)).r > 0.0) {
        d.yw = SMAASearchDiag2(SMAATexturePass2D(edgesTex), texcoord, vec2(1.0, 1.0), end);
        d.y += float(end.y > 0.9);
    } else {
        d.yw = vec2(0.0);
    }

    SMAA_BRANCH
    if (d.x + d.y > 2.0) {
        vec4 coords = mad(vec4(-d.x, -d.x, d.y, d.y), SMAA_RT_METRICS.xyxy, texcoord.xyxy);
        vec4 c;
        c.x  = SMAASampleLevelZeroOffset(edgesTex, coords.xy, ivec2(-1,  0)).g;
        c.y  = SMAASampleLevelZeroOffset(edgesTex, coords.xy, ivec2( 0, -1)).r;
        c.zw = SMAASampleLevelZeroOffset(edgesTex, coords.zw, ivec2( 1,  0)).gr;
        vec2 cc = mad(vec2(2.0), c.xz, c.yw);
        SMAAMovc(bvec2(step(0.9, d.zw)), cc, vec2(0.0));
        weights += SMAAAreaDiag(SMAATexturePass2D(areaTex), d.xy, cc, subsampleIndices.w).gr;
    }

    return weights;
}

// Horizontal/vertical search helpers
float SMAASearchLength(SMAATexture2D(searchTex), vec2 e, float offset) {
    vec2 scale = SMAA_SEARCHTEX_SIZE * vec2(0.5, -1.0);
    vec2 bias  = SMAA_SEARCHTEX_SIZE * vec2(offset, 1.0);
    scale += vec2(-1.0,  1.0);
    bias  += vec2( 0.5, -0.5);
    scale *= 1.0 / SMAA_SEARCHTEX_PACKED_SIZE;
    bias  *= 1.0 / SMAA_SEARCHTEX_PACKED_SIZE;
    return SMAA_SEARCHTEX_SELECT(SMAASampleLevelZero(searchTex, mad(scale, e, bias)));
}

float SMAASearchXLeft(SMAATexture2D(edgesTex), SMAATexture2D(searchTex), vec2 texcoord, float end) {
    vec2 e = vec2(0.0, 1.0);
    for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++) {
        if (!(texcoord.x > end && e.g > 0.8281 && e.r == 0.0)) break;
        e = SMAASampleLevelZero(edgesTex, texcoord).rg;
        texcoord = mad(-vec2(2.0, 0.0), SMAA_RT_METRICS.xy, texcoord);
    }
    float offset = mad(-(255.0 / 127.0), SMAASearchLength(SMAATexturePass2D(searchTex), e, 0.0), 3.25);
    return mad(SMAA_RT_METRICS.x, offset, texcoord.x);
}

float SMAASearchXRight(SMAATexture2D(edgesTex), SMAATexture2D(searchTex), vec2 texcoord, float end) {
    vec2 e = vec2(0.0, 1.0);
    for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++) {
        if (!(texcoord.x < end && e.g > 0.8281 && e.r == 0.0)) break;
        e = SMAASampleLevelZero(edgesTex, texcoord).rg;
        texcoord = mad(vec2(2.0, 0.0), SMAA_RT_METRICS.xy, texcoord);
    }
    float offset = mad(-(255.0 / 127.0), SMAASearchLength(SMAATexturePass2D(searchTex), e, 0.5), 3.25);
    return mad(-SMAA_RT_METRICS.x, offset, texcoord.x);
}

float SMAASearchYUp(SMAATexture2D(edgesTex), SMAATexture2D(searchTex), vec2 texcoord, float end) {
    vec2 e = vec2(1.0, 0.0);
    for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++) {
        if (!(texcoord.y > end && e.r > 0.8281 && e.g == 0.0)) break;
        e = SMAASampleLevelZero(edgesTex, texcoord).rg;
        texcoord = mad(-vec2(0.0, 2.0), SMAA_RT_METRICS.xy, texcoord);
    }
    float offset = mad(-(255.0 / 127.0), SMAASearchLength(SMAATexturePass2D(searchTex), e.gr, 0.0), 3.25);
    return mad(SMAA_RT_METRICS.y, offset, texcoord.y);
}

float SMAASearchYDown(SMAATexture2D(edgesTex), SMAATexture2D(searchTex), vec2 texcoord, float end) {
    vec2 e = vec2(1.0, 0.0);
    for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++) {
        if (!(texcoord.y < end && e.r > 0.8281 && e.g == 0.0)) break;
        e = SMAASampleLevelZero(edgesTex, texcoord).rg;
        texcoord = mad(vec2(0.0, 2.0), SMAA_RT_METRICS.xy, texcoord);
    }
    float offset = mad(-(255.0 / 127.0), SMAASearchLength(SMAATexturePass2D(searchTex), e.gr, 0.5), 3.25);
    return mad(-SMAA_RT_METRICS.y, offset, texcoord.y);
}

vec2 SMAAArea(SMAATexture2D(areaTex), vec2 dist, float e1, float e2, float offset) {
    vec2 texcoord = mad(vec2(SMAA_AREATEX_MAX_DISTANCE), round(4.0 * vec2(e1, e2)), dist);
    texcoord = mad(SMAA_AREATEX_PIXEL_SIZE, texcoord, 0.5 * SMAA_AREATEX_PIXEL_SIZE);
    texcoord.y = mad(SMAA_AREATEX_SUBTEX_SIZE, offset, texcoord.y);
    return SMAA_AREATEX_SELECT(SMAASampleLevelZero(areaTex, texcoord));
}

// Corner detection
void SMAADetectHorizontalCornerPattern(SMAATexture2D(edgesTex), inout vec2 weights,
                                        vec4 texcoord, vec2 d) {
    #if !defined(SMAA_DISABLE_CORNER_DETECTION)
    vec2 leftRight = step(d.xy, d.yx);
    vec2 rounding = (1.0 - SMAA_CORNER_ROUNDING_NORM) * leftRight;
    rounding /= leftRight.x + leftRight.y;
    vec2 factor = vec2(1.0);
    factor.x -= rounding.x * SMAASampleLevelZeroOffset(edgesTex, texcoord.xy, ivec2(0,  1)).r;
    factor.x -= rounding.y * SMAASampleLevelZeroOffset(edgesTex, texcoord.zw, ivec2(1,  1)).r;
    factor.y -= rounding.x * SMAASampleLevelZeroOffset(edgesTex, texcoord.xy, ivec2(0, -2)).r;
    factor.y -= rounding.y * SMAASampleLevelZeroOffset(edgesTex, texcoord.zw, ivec2(1, -2)).r;
    weights *= saturate(factor);
    #endif
}

void SMAADetectVerticalCornerPattern(SMAATexture2D(edgesTex), inout vec2 weights,
                                      vec4 texcoord, vec2 d) {
    #if !defined(SMAA_DISABLE_CORNER_DETECTION)
    vec2 leftRight = step(d.xy, d.yx);
    vec2 rounding = (1.0 - SMAA_CORNER_ROUNDING_NORM) * leftRight;
    rounding /= leftRight.x + leftRight.y;
    vec2 factor = vec2(1.0);
    factor.x -= rounding.x * SMAASampleLevelZeroOffset(edgesTex, texcoord.xy, ivec2( 1,  0)).g;
    factor.x -= rounding.y * SMAASampleLevelZeroOffset(edgesTex, texcoord.zw, ivec2( 1,  1)).g;
    factor.y -= rounding.x * SMAASampleLevelZeroOffset(edgesTex, texcoord.xy, ivec2(-2,  0)).g;
    factor.y -= rounding.y * SMAASampleLevelZeroOffset(edgesTex, texcoord.zw, ivec2(-2,  1)).g;
    weights *= saturate(factor);
    #endif
}

// =============================================================================
// PASS 2 — BLENDING WEIGHT CALCULATION PS
// Input:  edgesTex (colortex9), areaTex (colortex11), searchTex (colortex12)
// Output: vec4 weights written to colortex10
// subsampleIndices = vec4(0.0) for SMAA 1x
// =============================================================================

vec4 SMAABlendingWeightCalculationPS(vec2 texcoord, vec2 pixcoord, vec4 offset[3],
                                      SMAATexture2D(edgesTex), SMAATexture2D(areaTex),
                                      SMAATexture2D(searchTex), vec4 subsampleIndices) {
    vec4 weights = vec4(0.0);
    vec2 e = SMAASample(edgesTex, texcoord).rg;

    SMAA_BRANCH
    if (e.g > 0.0) {
        #if !defined(SMAA_DISABLE_DIAG_DETECTION)
        weights.rg = SMAACalculateDiagWeights(SMAATexturePass2D(edgesTex),
                                               SMAATexturePass2D(areaTex),
                                               texcoord, e, subsampleIndices);
        SMAA_BRANCH
        if (weights.r == -weights.g) {
        #endif
            vec2 d;
            vec3 coords;
            coords.x = SMAASearchXLeft(SMAATexturePass2D(edgesTex), SMAATexturePass2D(searchTex),
                                        offset[0].xy, offset[2].x);
            coords.y = offset[1].y;
            d.x = coords.x;
            float e1 = SMAASampleLevelZero(edgesTex, coords.xy).r;
            coords.z = SMAASearchXRight(SMAATexturePass2D(edgesTex), SMAATexturePass2D(searchTex),
                                         offset[0].zw, offset[2].y);
            d.y = coords.z;
            d = abs(round(mad(SMAA_RT_METRICS.zz, d, -pixcoord.xx)));
            vec2 sqrt_d = sqrt(d);
            float e2 = SMAASampleLevelZeroOffset(edgesTex, coords.zy, ivec2(1, 0)).r;
            weights.rg = SMAAArea(SMAATexturePass2D(areaTex), sqrt_d, e1, e2, subsampleIndices.y);
            coords.y = texcoord.y;
            SMAADetectHorizontalCornerPattern(SMAATexturePass2D(edgesTex), weights.rg,
                                               coords.xyzy, d);
        #if !defined(SMAA_DISABLE_DIAG_DETECTION)
        } else {
            e.r = 0.0;
        }
        #endif
    }

    SMAA_BRANCH
    if (e.r > 0.0) {
        vec2 d;
        vec3 coords;
        coords.y = SMAASearchYUp(SMAATexturePass2D(edgesTex), SMAATexturePass2D(searchTex),
                                  offset[1].xy, offset[2].z);
        coords.x = offset[0].x;
        d.x = coords.y;
        float e1 = SMAASampleLevelZero(edgesTex, coords.xy).g;
        coords.z = SMAASearchYDown(SMAATexturePass2D(edgesTex), SMAATexturePass2D(searchTex),
                                    offset[1].zw, offset[2].w);
        d.y = coords.z;
        d = abs(round(mad(SMAA_RT_METRICS.ww, d, -pixcoord.yy)));
        vec2 sqrt_d = sqrt(d);
        float e2 = SMAASampleLevelZeroOffset(edgesTex, coords.xz, ivec2(0, 1)).g;
        weights.ba = SMAAArea(SMAATexturePass2D(areaTex), sqrt_d, e1, e2, subsampleIndices.x);
        coords.x = texcoord.x;
        SMAADetectVerticalCornerPattern(SMAATexturePass2D(edgesTex), weights.ba,
                                         coords.xyxz, d);
    }

    return weights;
}

// =============================================================================
// PASS 3 — NEIGHBOURHOOD BLENDING PS
// Input:  colorTex (colortex3), blendTex (colortex10)
// Output: vec4 final antialiased color written back to colortex3
// =============================================================================

vec4 SMAANeighborhoodBlendingPS(vec2 texcoord, vec4 offset,
                                 SMAATexture2D(colorTex), SMAATexture2D(blendTex)) {
    vec4 a;
    a.x = SMAASample(blendTex, offset.xy).a;   // Right
    a.y = SMAASample(blendTex, offset.zw).g;   // Top
    a.wz = SMAASample(blendTex, texcoord).xz;  // Bottom / Left

    SMAA_BRANCH
    if (dot(a, vec4(1.0)) < 1e-5) {
        return SMAASampleLevelZero(colorTex, texcoord);
    } else {
        bool h = max(a.x, a.z) > max(a.y, a.w);
        vec4 blendingOffset = vec4(0.0, a.y, 0.0, a.w);
        vec2 blendingWeight = a.yw;
        SMAAMovc(bvec4(h, h, h, h), blendingOffset, vec4(a.x, 0.0, a.z, 0.0));
        SMAAMovc(bvec2(h, h), blendingWeight, a.xz);
        blendingWeight /= dot(blendingWeight, vec2(1.0));
        vec4 blendingCoord = mad(blendingOffset,
                                  vec4(SMAA_RT_METRICS.xy, -SMAA_RT_METRICS.xy),
                                  texcoord.xyxy);
        vec4 color = blendingWeight.x * SMAASampleLevelZero(colorTex, blendingCoord.xy);
        color += blendingWeight.y * SMAASampleLevelZero(colorTex, blendingCoord.zw);
        return color;
    }
}
