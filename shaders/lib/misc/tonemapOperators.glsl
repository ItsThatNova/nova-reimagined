/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

// Tonemap operator implementations for use with OTHER_TONEMAP.
// Input is raw linear scene color — no TM_EXPOSURE applied.
// CU scene values are already in a normalized HDR range (roughly 0.0-2.0+),
// so reference pre-scales designed for physically-based units are not used.
// Output is linear, ready for LinearToRGB sRGB gamma encoding.

// Rec.709 luminance weights for operator luminance calculations
const vec3 tm_luma = vec3(0.2126, 0.7152, 0.0722);

// sRGB EOTF inverse — used by Hejl-Burgess which encodes its own gamma
vec3 tm_srgb_eotf_inv(vec3 x) {
    return x * (x * (x * 0.305306011 + 0.682171111) + 0.012522878);
}

// ---- Reinhard ----
vec3 tonemap_reinhard(vec3 rgb) {
    return rgb / (rgb + 1.0);
}

// ---- Reinhard-Jodie ----
vec3 tonemap_reinhard_jodie(vec3 rgb) {
    vec3 reinhard = rgb / (rgb + 1.0);
    return mix(rgb / (dot(rgb, tm_luma) + 1.0), reinhard, reinhard);
}

// ---- Hejl-Burgess (filmic) ----
vec3 tonemap_hejl_burgess(vec3 rgb) {
    rgb = max(vec3(0.0), rgb - 0.004);
    rgb = (rgb * (6.2 * rgb + 0.5)) / (rgb * (6.2 * rgb + 1.7) + 0.06);
    return tm_srgb_eotf_inv(rgb);
}

// ---- Hejl 2015 ----
vec3 tonemap_hejl_2015(vec3 rgb) {
    const float white_point = 5.0;
    vec4 vh = vec4(rgb, white_point);
    vec4 va = (1.425 * vh) + 0.05;
    vec4 vf = ((vh * va + 0.004) / ((vh * (va + 0.55) + 0.0491))) - 0.0821;
    return vf.rgb / vf.www;
}

// ---- Uncharted 2 / Hable ----
vec3 tonemap_uncharted2_partial(vec3 rgb) {
    const float a = 0.15, b = 0.50, c = 0.10, d = 0.20, e = 0.02, f = 0.30;
    return ((rgb * (a * rgb + (c * b)) + (d * e)) / (rgb * (a * rgb + b) + (d * f))) - e / f;
}
vec3 tonemap_uncharted2(vec3 rgb) {
    const vec3 w = vec3(11.2);
    return tonemap_uncharted2_partial(rgb) / tonemap_uncharted2_partial(w);
}

// ---- ACES fit (Stephen Hill approximation) ----
// Scaled down slightly as ACES curve expects values that can exceed 1.0 significantly.
// CU scene values are already in a normalized range so we scale down before the curve.
vec3 tonemap_aces_fit(vec3 rgb) {
    rgb *= 0.6;
    const mat3 input_mat = mat3(
         0.59719,  0.07600,  0.02840,
         0.35458,  0.90834,  0.13383,
         0.04823,  0.01566,  0.83777
    );
    const mat3 output_mat = mat3(
         1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    rgb = input_mat * rgb;
    vec3 a = rgb * (rgb + 0.0245786) - 0.000090537;
    vec3 b = rgb * (0.983729 * rgb + 0.4329510) + 0.238081;
    return clamp(output_mat * (a / b), 0.0, 1.0);
}

// ---- Lottes 2016 ----
vec3 tonemap_lottes(vec3 rgb) {
    const vec3 a       = vec3(1.6);
    const vec3 d       = vec3(0.977);
    const vec3 hdr_max = vec3(8.0);
    const vec3 mid_in  = vec3(0.18);
    const vec3 mid_out = vec3(0.267);
    const vec3 b =
        (-pow(mid_in, a) + pow(hdr_max, a) * mid_out) /
        ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    const vec3 c =
        (pow(hdr_max, a * d) * pow(mid_in, a) - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out) /
        ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    return pow(rgb, a) / (pow(rgb, a * d) * b + c);
}

// ---- Dispatch ----
vec3 ApplyTonemapOperator(vec3 color) {
    color *= OTHER_TONEMAP_EXPOSURE;

    // Contrast: power curve — exponent > 1.0 increases contrast, < 1.0 reduces it
    color = pow(max(color, vec3(0.0)), vec3(OTHER_TONEMAP_CONTRAST));

    float initialLuminance = dot(color, tm_luma);

    vec3 tonemapped;
    #if TONEMAP_OPERATOR == 1
        tonemapped = tonemap_reinhard(color);
    #elif TONEMAP_OPERATOR == 2
        tonemapped = tonemap_reinhard_jodie(color);
    #elif TONEMAP_OPERATOR == 3
        tonemapped = tonemap_hejl_burgess(color);
    #elif TONEMAP_OPERATOR == 4
        tonemapped = tonemap_hejl_2015(color);
    #elif TONEMAP_OPERATOR == 5
        tonemapped = tonemap_uncharted2(color);
    #elif TONEMAP_OPERATOR == 6
        tonemapped = tonemap_aces_fit(color);
    #elif TONEMAP_OPERATOR == 7
        tonemapped = tonemap_lottes(color);
    #else
        tonemapped = tonemap_reinhard(color);
    #endif

    // Dark lift: blend shadow areas toward simple gamma to prevent crushing
    float darkLift = smoothstep(0.1, 0.0, initialLuminance);
    vec3 smoothColor = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
    vec3 result = mix(tonemapped, smoothColor, darkLift * OTHER_TONEMAP_DARK_LIFT);

    // Highlight compression: softly compresses values approaching white
    // 1.0 = no effect, lower values compress highlights progressively
    result = result / (result + OTHER_TONEMAP_HIGHLIGHT_CLAMP * (1.0 - result));

    // Saturation: post-operator saturation adjustment
    float luma = dot(result, tm_luma);
    result = clamp(mix(vec3(luma), result, OTHER_TONEMAP_SATURATION), 0.0, 1.0);

    return result;
}
