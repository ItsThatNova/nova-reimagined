#ifndef INCLUDE_SKY
    #define INCLUDE_SKY

    #include "/lib/colors/lightAndAmbientColors.glsl"
    #include "/lib/colors/skyColors.glsl"

    #ifdef CAVE_FOG
        #include "/lib/atmospherics/fog/caveFactor.glsl"
    #endif

    vec3 GetSky(float VdotU, float VdotS, float dither, bool doGlare, bool doGround) {
        // Prepare variables
        float nightFactorSqrt2 = sqrt2(nightFactor);
        float nightFactorM = sqrt2(nightFactorSqrt2) * 0.4;
        float VdotSM1 = pow2(max(VdotS, 0.0));
        float VdotSM2 = pow2(VdotSM1);
        float VdotSM3 = pow2(pow2(max(-VdotS, 0.0)));
        float VdotSML = sunVisibility > 0.5 ? VdotS : -VdotS;

        float VdotUmax0 = max(VdotU, 0.0);
        float VdotUmax0M = 1.0 - pow2(VdotUmax0);

        // Prepare colors
        vec3 upColor = mix(nightUpSkyColor * (1.5 - 0.5 * nightFactorSqrt2 + nightFactorM * VdotSM3 * 1.5), dayUpSkyColor, sunFactor);
        vec3 middleColor = mix(nightMiddleSkyColor * (3.0 - 2.0 * nightFactorSqrt2), dayMiddleSkyColor * (1.0 + VdotSM2 * 0.3), sunFactor);
        vec3 downColor = mix(nightDownSkyColor, dayDownSkyColor, (sunFactor + sunVisibility) * 0.5);

        // Mix the colors
            // Set sky gradient
            float VdotUM1 = pow2(1.0 - VdotUmax0);
                  VdotUM1 = pow(VdotUM1, 1.0 - VdotSM2 * 0.4);
                  VdotUM1 = mix(VdotUM1, 1.0, rainFactor2 * WEATHER_SKY_OVERCAST);
            vec3 finalSky = mix(upColor, middleColor, VdotUM1);

            // Add sunset color
            float VdotUM2 = pow2(1.0 - abs(VdotU));
                  VdotUM2 = VdotUM2 * VdotUM2 * (3.0 - 2.0 * VdotUM2);
                  VdotUM2 *= (0.7 - nightFactorM + VdotSM1 * (0.3 + nightFactorM)) * invNoonFactor * sunFactor;
            finalSky = mix(finalSky, sunsetDownSkyColorP * (1.0 + VdotSM1 * 0.3), VdotUM2 * invRainFactor);

            // Add sky ground with fake light scattering
            float VdotUM3 = min(max0(-VdotU + 0.08) / 0.35, 1.0);
                  VdotUM3 = smoothstep1(VdotUM3);
            vec3 scatteredGroundMixer = vec3(VdotUM3 * VdotUM3, sqrt1(VdotUM3), sqrt3(VdotUM3));
                 scatteredGroundMixer = mix(vec3(VdotUM3), scatteredGroundMixer, 0.75 - WEATHER_SKY_HORIZON * rainFactor);
            finalSky = mix(finalSky, downColor, scatteredGroundMixer);
        //

        // Sky Ground
        if (doGround)
            finalSky *= smoothstep1(pow2(1.0 + min(VdotU, 0.0)));

        // Apply Underwater Fog / underwater horizon band control
        if (isEyeInWater == 1) {
            float uwbfNightWeight = 1.0 - sunVisibility2;
            float uwbfDuskWeight  = sunVisibility2 * (1.0 - noonFactor);
            float uwbfDayWeight   = sunVisibility2 * noonFactor;
            float underwaterBorderFogBrightness =
                uwbfDayWeight   * UNDERWATERBORDERFOG_DAY_BRIGHTNESS   * 0.01 +
                uwbfDuskWeight  * UNDERWATERBORDERFOG_DUSK_BRIGHTNESS  * 0.01 +
                uwbfNightWeight * UNDERWATERBORDERFOG_NIGHT_BRIGHTNESS * 0.01;
            vec3 underwaterHorizonColor = waterFogColor * underwaterBorderFogBrightness;
            finalSky = mix(finalSky * 3.0, underwaterHorizonColor, VdotUmax0M);
        }

        // Sun/Moon Glare
        if (doGlare) {
            if (0.0 < VdotSML) {
                float glareScatter = 3.0 * (2.0 - clamp01(VdotS * 1000.0));
                #ifndef SUN_MOON_DURING_RAIN
                    glareScatter *= 1.0 - WEATHER_SKY_GLARE_SCATTER * rainFactor2;
                #endif
                float VdotSM4 = pow(abs(VdotS), glareScatter);

                float visfactor = 0.070;
                float glare = visfactor / (1.0 - (1.0 - visfactor) * VdotSM4) - visfactor;
                glare *= 0.58;

                float glareWaterFactor = isEyeInWater * sunVisibility;
                vec3 glareColor = mix(vec3(0.38, 0.4, 0.5) * 0.3, vec3(1.5, 0.7, 0.3) + vec3(0.0, 0.5, 0.5) * noonFactor, sunVisibility);
                     glareColor = glareColor + glareWaterFactor * vec3(7.0);

                #ifdef SUN_MOON_DURING_RAIN
                    glare *= 1.0 - WEATHER_SKY_GLARE_INTENSITY * 0.6 * rainFactor;
                #else
                    glare *= 1.0 - WEATHER_SKY_GLARE_INTENSITY * rainFactor;
                #endif
                // Time-of-day weighted glare desaturation during rain.
                // At 1.0 (default) reproduces original Style 1 (0.5 * rainFactor).
                float rainTimedGD  = mix(RAIN_NIGHT_GLARE_DESAT,  mix(RAIN_DUSK_GLARE_DESAT,  RAIN_DAY_GLARE_DESAT,  noonFactor), sunVisibility2);
                float stormTimedGD = mix(STORM_NIGHT_GLARE_DESAT, mix(STORM_DUSK_GLARE_DESAT, STORM_DAY_GLARE_DESAT, noonFactor), sunVisibility2);
                float rainTimedGD_final = mix(rainTimedGD, stormTimedGD, GetThunderFactor());
                float glareDesaturateFactor = 0.5 * rainFactor * rainTimedGD_final;
                glareColor = mix(glareColor, vec3(GetLuminance(glareColor)), glareDesaturateFactor);

                finalSky += glareColor * glare * shadowTime;
            }
        }

        #ifdef CAVE_FOG
            // Apply Cave Fog
            finalSky = mix(finalSky, caveFogColor, GetCaveFactor() * VdotUmax0M);
        #endif

        // Dither to fix banding
        finalSky += (dither - 0.5) / 128.0;

        float skyLuma = dot(finalSky, vec3(0.299, 0.587, 0.114));
        float effectiveSaturation = mix(SKY_SATURATION, WEATHER_SKY_SATURATION, rainFactor);
        vec3 weatherSkyColor = mix(
            vec3(SKY_COLOR_R, SKY_COLOR_G, SKY_COLOR_B),
            vec3(WEATHER_SKY_COLOR_R, WEATHER_SKY_COLOR_G, WEATHER_SKY_COLOR_B),
            rainFactor);
        finalSky = mix(vec3(skyLuma), finalSky, effectiveSaturation) * weatherSkyColor;

        return finalSky;
    }

    vec3 GetLowQualitySky(float VdotU, float VdotS, float dither, bool doGlare, bool doGround) {
        // Prepare variables
        float VdotUmax0 = max(VdotU, 0.0);
        float VdotUmax0M = 1.0 - pow2(VdotUmax0);

        // Prepare colors
        vec3 upColor = mix(nightUpSkyColor, dayUpSkyColor, sunFactor);
        vec3 middleColor = mix(nightMiddleSkyColor, dayMiddleSkyColor, sunFactor);

        // Mix the colors
            // Set sky gradient
            float VdotUM1 = pow2(1.0 - VdotUmax0);
                  VdotUM1 = mix(VdotUM1, 1.0, rainFactor2 * WEATHER_SKY_OVERCAST);
            vec3 finalSky = mix(upColor, middleColor, VdotUM1);

            // Add sunset color
            float VdotUM2 = pow2(1.0 - abs(VdotU));
                  VdotUM2 *= invNoonFactor * sunFactor * (0.8 + 0.2 * VdotS);
            finalSky = mix(finalSky, sunsetDownSkyColorP * (shadowTime * 0.6 + 0.2), VdotUM2 * invRainFactor);
        //

        // Sky Ground
        finalSky *= pow2(pow2(1.0 + min(VdotU, 0.0)));

        // Apply Underwater Fog / underwater horizon band control
        if (isEyeInWater == 1) {
            float uwbfNightWeight = 1.0 - sunVisibility2;
            float uwbfDuskWeight  = sunVisibility2 * (1.0 - noonFactor);
            float uwbfDayWeight   = sunVisibility2 * noonFactor;
            float underwaterBorderFogBrightness =
                uwbfDayWeight   * UNDERWATERBORDERFOG_DAY_BRIGHTNESS   * 0.01 +
                uwbfDuskWeight  * UNDERWATERBORDERFOG_DUSK_BRIGHTNESS  * 0.01 +
                uwbfNightWeight * UNDERWATERBORDERFOG_NIGHT_BRIGHTNESS * 0.01;
            vec3 underwaterHorizonColor = waterFogColor * underwaterBorderFogBrightness;
            finalSky = mix(finalSky, underwaterHorizonColor, VdotUmax0M);
        }

        // Sun/Moon Glare
        finalSky *= 1.0 + mix(nightFactor, 0.5 + 0.7 * noonFactor, VdotS * 0.5 + 0.5) * pow2(pow2(pow2(VdotS)));

        #ifdef CAVE_FOG
            // Apply Cave Fog
            finalSky = mix(finalSky, caveFogColor, GetCaveFactor() * VdotUmax0M);
        #endif

        float skyLumaLQ = dot(finalSky, vec3(0.299, 0.587, 0.114));
        float effectiveSaturationLQ = mix(SKY_SATURATION, WEATHER_SKY_SATURATION, rainFactor);
        vec3 weatherSkyColorLQ = mix(
            vec3(SKY_COLOR_R, SKY_COLOR_G, SKY_COLOR_B),
            vec3(WEATHER_SKY_COLOR_R, WEATHER_SKY_COLOR_G, WEATHER_SKY_COLOR_B),
            rainFactor);
        finalSky = mix(vec3(skyLumaLQ), finalSky, effectiveSaturationLQ) * weatherSkyColorLQ;

        return finalSky;
    }

#endif //INCLUDE_SKY