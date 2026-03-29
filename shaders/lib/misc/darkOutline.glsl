vec2 darkOutlineOffsets[12] = vec2[12](
                               vec2( 1.0,0.0),
                               vec2(-1.0,1.0),
                               vec2( 0.0,1.0),
                               vec2( 1.0,1.0),
                               vec2(-2.0,2.0),
                               vec2(-1.0,2.0),
                               vec2( 0.0,2.0),
                               vec2( 1.0,2.0),
                               vec2( 2.0,2.0),
                               vec2(-2.0,1.0),
                               vec2( 2.0,1.0),
                               vec2( 2.0,0.0)
);

void DoDarkOutline(inout vec3 color, float z0, float fadeFactor) {
    vec2 scale = vec2(1.0 / view);

    float outline = 1.0;
    float z = GetLinearDepth(z0) * far * 2.0;
    float minZ = 1.0, sampleZA = 0.0, sampleZB = 0.0;

    // 50/100: 4 samples (1px radius), blend scaled by weight.
    // 150:    12 samples (1px + 2px radius), blend at 1.0 — wider kernel produces thicker line.
    #if DARK_OUTLINE_WEIGHT > 100
        int sampleCount = 12;
        float blendWeight = 1.0;
    #else
        int sampleCount = 4;
        float blendWeight = DARK_OUTLINE_WEIGHT * 0.01;
    #endif

    for (int i = 0; i < sampleCount; i++) {
        vec2 offset = scale * darkOutlineOffsets[i];
        sampleZA = texture2D(depthtex0, texCoord + offset).r;
        sampleZB = texture2D(depthtex0, texCoord - offset).r;

        // Fall back to depthtex1 (includes translucent geometry like water) when
        // depthtex0 returns sky. Without this, water neighbours read as sky or as
        // the terrain behind the water, causing inconsistent outlines on leaves and
        // other geometry viewed against a water backdrop.
        if (sampleZA >= 1.0) sampleZA = texture2D(depthtex1, texCoord + offset).r;
        if (sampleZB >= 1.0) sampleZB = texture2D(depthtex1, texCoord - offset).r;

        // Silhouette detection: neighbour is sky or DH terrain (not in depthtex0).
        // Current pixel is shallower than sky so the depth check would never fire here.
        if (sampleZA >= 1.0 || sampleZB >= 1.0) {
            outline = 0.0;
            break;
        }

        float sampleZsum = GetLinearDepth(sampleZA) + GetLinearDepth(sampleZB);
        outline *= clamp(1.0 - (z - sampleZsum * far), 0.0, 1.0);
        minZ = min(minZ, min(sampleZA, sampleZB));
    }

    if (outline < 0.909091) {
        color = mix(color, vec3(0.0), (1.0 - outline * 1.1) * fadeFactor * blendWeight);
    }
}

#ifdef DISTANT_HORIZONS
// Convert DH raw depth to actual view-space distance using dhProjectionInverse.
// Cannot use vanilla GetLinearDepth() - DH uses completely different near/far planes.
float GetLinearDepthDH(float depth) {
    vec4 pos = dhProjectionInverse * vec4(0.0, 0.0, depth * 2.0 - 1.0, 1.0);
    return abs(pos.z / pos.w);
}

void DoDarkOutlineDH(inout vec3 color, float z0DH, float fadeFactor) {
    vec2 scale = vec2(1.0 / view);

    float outline = 1.0;
    // Centre depth in view-space blocks. Sky (z0DH=1.0) gives DH far plane distance.
    float z = GetLinearDepthDH(z0DH);
    float minZ = 1.0, sampleZA = 0.0, sampleZB = 0.0;

    // 50/100: 4 samples (1px radius), blend scaled by weight.
    // 150:    12 samples (1px + 2px radius), blend at 1.0 — wider kernel produces thicker line.
    #if DARK_OUTLINE_WEIGHT > 100
        int sampleCount = 12;
        float blendWeight = 1.0;
    #else
        int sampleCount = 4;
        float blendWeight = DARK_OUTLINE_WEIGHT * 0.01;
    #endif

    for (int i = 0; i < sampleCount; i++) {
        vec2 offset = scale * darkOutlineOffsets[i];
        sampleZA = texture2D(dhDepthTex, texCoord + offset).r;
        sampleZB = texture2D(dhDepthTex, texCoord - offset).r;

        // Silhouette detection: neighbour is sky (no DH geometry here either).
        if (sampleZA >= 1.0 || sampleZB >= 1.0) {
            outline = 0.0;
            break;
        }

        // Sum of view-space distances of both neighbours
        float sampleZsum = GetLinearDepthDH(sampleZA) + GetLinearDepthDH(sampleZB);
        // Same formula as vanilla but without the far scaling - already in block units
        outline *= clamp(1.0 - (z - sampleZsum * 0.5), 0.0, 1.0);
        minZ = min(minZ, min(sampleZA, sampleZB));
    }

    if (outline < 0.909091) {
        color = mix(color, vec3(0.0), (1.0 - outline * 1.1) * fadeFactor * blendWeight);
    }
}
#endif
