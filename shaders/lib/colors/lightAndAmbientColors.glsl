#ifndef INCLUDE_LIGHT_AND_AMBIENT_COLORS
    #define INCLUDE_LIGHT_AND_AMBIENT_COLORS

    #if defined OVERWORLD
        #ifndef COMPOSITE1
            vec3 noonClearLightColor = vec3(0.65, 0.55, 0.375) * 2.05; //ground and cloud color
        #else
            vec3 noonClearLightColor = vec3(0.4, 0.75, 1.3); //light shaft color
        #endif
        vec3 noonClearAmbientColor = pow(skyColor, vec3(0.75)) * 0.85;

        #ifndef COMPOSITE1
            vec3 sunsetClearLightColor = pow(vec3(0.64, 0.45, 0.3), vec3(1.5 + invNoonFactor)) * 5.0; //ground and cloud color
        #else
            vec3 sunsetClearLightColor = pow(vec3(0.62, 0.39, 0.24), vec3(1.5 + invNoonFactor)) * 6.8; //light shaft color
        #endif
        vec3 sunsetClearAmbientColor   = noonClearAmbientColor * vec3(1.21, 0.92, 0.76) * 0.95;

        #if !defined COMPOSITE1 && !defined DEFERRED1
            vec3 nightClearLightColor = 0.9 * vec3(0.15, 0.14, 0.20) * (0.4 + vsBrightness * 0.4); //ground color
        #elif defined DEFERRED1
            vec3 nightClearLightColor = 0.9 * vec3(0.11, 0.14, 0.20); //cloud color
        #else
            vec3 nightClearLightColor = vec3(0.08, 0.12, 0.23); //light shaft color
        #endif
        vec3 nightClearAmbientColor   = 0.9 * vec3(0.09, 0.12, 0.17) * (1.55 + vsBrightness * 0.77);

        // Biome-specific colour shifts — always active, scaled by BIOME_WEATHER_COLOR_I.
        // At 0.0 snowy/dry biomes get no extra light colour modification.
        vec3 drlcSnowM = inSnowy * vec3(-0.06, 0.0, 0.04)  * BIOME_WEATHER_COLOR_I;
        vec3 drlcDryM  = inDry   * vec3(0.01, -0.035, -0.06) * BIOME_WEATHER_COLOR_I;
        // No rain-specific direct light colour shift — controlled via Warmth sliders.
        vec3 drlcRainM = vec3(0.0);

        // Base rain light and ambient colors — unchanged from original Style 1.
        vec3 dayRainLightColor   = vec3(0.21, 0.16, 0.13) * 0.85 + noonFactor * vec3(0.0, 0.02, 0.06)
                                 + drlcRainM + drlcSnowM + drlcDryM;
        vec3 dayRainAmbientColor = vec3(0.2, 0.2, 0.25) * (1.8 + 0.5 * vsBrightness);

        vec3 nightRainLightColor   = vec3(0.03, 0.035, 0.05) * (0.5 + 0.5 * vsBrightness);
        vec3 nightRainAmbientColor = vec3(0.16, 0.20, 0.3) * (0.75 + 0.6 * vsBrightness);

        #ifndef COMPOSITE1
            float noonFactorDM = noonFactor; //ground and cloud factor
        #else
            float noonFactorDM = noonFactor * noonFactor; //light shaft factor
        #endif
        vec3 dayLightColor   = mix(sunsetClearLightColor, noonClearLightColor, noonFactorDM);
        vec3 dayAmbientColor = mix(sunsetClearAmbientColor, noonClearAmbientColor, noonFactorDM);

        vec3 clearLightColor   = mix(nightClearLightColor, dayLightColor, sunVisibility2);
        vec3 clearAmbientColor = mix(nightClearAmbientColor, dayAmbientColor, sunVisibility2);

        float rainShadowVisReduce = 0.0
            #ifdef SUN_MOON_DURING_RAIN
                + (0.2 * inSnowy + 0.2 * inDry) * BIOME_WEATHER_COLOR_I
            #else
                + 0.4
            #endif
        ;

        // Time-of-day weights: blend between night, dawn/dusk, and day.
        // duskWeight peaks when sun is up but not near noon (sunrise/sunset).
        float rainNightWeight = 1.0 - sunVisibility2;
        float rainDuskWeight  = sunVisibility2 * (1.0 - noonFactor);
        float rainDayWeight   = sunVisibility2 * noonFactor;

        // Blend rain and storm values per-slider based on thunderStrength.
        float thunderFactor = GetThunderFactor();

        // Warmth multipliers blended between rain and storm per time-of-day.
        float lightWarmthDayV   = mix(RAIN_DAY_LIGHT_WARMTH,   STORM_DAY_LIGHT_WARMTH,   thunderFactor);
        float lightWarmthDuskV  = mix(RAIN_DUSK_LIGHT_WARMTH,  STORM_DUSK_LIGHT_WARMTH,  thunderFactor);
        float lightWarmthNightV = mix(RAIN_NIGHT_LIGHT_WARMTH, STORM_NIGHT_LIGHT_WARMTH, thunderFactor);
        vec3 lightWarmthDay   = vec3(lightWarmthDayV,   1.0, 2.0 - lightWarmthDayV);
        vec3 lightWarmthDusk  = vec3(lightWarmthDuskV,  1.0, 2.0 - lightWarmthDuskV);
        vec3 lightWarmthNight = vec3(lightWarmthNightV, 1.0, 2.0 - lightWarmthNightV);

        float ambWarmthDayV   = mix(RAIN_DAY_AMBIENT_WARMTH,   STORM_DAY_AMBIENT_WARMTH,   thunderFactor);
        float ambWarmthDuskV  = mix(RAIN_DUSK_AMBIENT_WARMTH,  STORM_DUSK_AMBIENT_WARMTH,  thunderFactor);
        float ambWarmthNightV = mix(RAIN_NIGHT_AMBIENT_WARMTH, STORM_NIGHT_AMBIENT_WARMTH, thunderFactor);
        vec3 ambWarmthDay   = vec3(ambWarmthDayV,   1.0, 2.0 - ambWarmthDayV);
        vec3 ambWarmthDusk  = vec3(ambWarmthDuskV,  1.0, 2.0 - ambWarmthDuskV);
        vec3 ambWarmthNight = vec3(ambWarmthNightV, 1.0, 2.0 - ambWarmthNightV);

        // Blend rain and storm intensity values.
        float lightIntensity = mix(
            rainDayWeight * RAIN_DAY_LIGHT_INTENSITY + rainDuskWeight * RAIN_DUSK_LIGHT_INTENSITY + rainNightWeight * RAIN_NIGHT_LIGHT_INTENSITY,
            rainDayWeight * STORM_DAY_LIGHT_INTENSITY + rainDuskWeight * STORM_DUSK_LIGHT_INTENSITY + rainNightWeight * STORM_NIGHT_LIGHT_INTENSITY,
            thunderFactor);

        float ambIntensity = mix(
            rainDayWeight * RAIN_DAY_AMBIENT_INTENSITY + rainDuskWeight * RAIN_DUSK_AMBIENT_INTENSITY + rainNightWeight * RAIN_NIGHT_AMBIENT_INTENSITY,
            rainDayWeight * STORM_DAY_AMBIENT_INTENSITY + rainDuskWeight * STORM_DUSK_AMBIENT_INTENSITY + rainNightWeight * STORM_NIGHT_AMBIENT_INTENSITY,
            thunderFactor);

        vec3 rainLightColor = lightIntensity * (
            (lightWarmthDay   * mix(nightRainLightColor, dayRainLightColor * (1.0 - rainShadowVisReduce), sunVisibility2) * 2.5) * rainDayWeight +
            (lightWarmthDusk  * mix(nightRainLightColor, dayRainLightColor * (1.0 - rainShadowVisReduce), sunVisibility2) * 2.5) * rainDuskWeight +
            (lightWarmthNight * nightRainLightColor * 2.5) * rainNightWeight);

        vec3 rainAmbientColor = ambIntensity * (
            (ambWarmthDay   * mix(nightRainAmbientColor, dayRainAmbientColor * (1.0 + rainShadowVisReduce), sunVisibility2)) * rainDayWeight +
            (ambWarmthDusk  * mix(nightRainAmbientColor, dayRainAmbientColor * (1.0 + rainShadowVisReduce), sunVisibility2)) * rainDuskWeight +
            (ambWarmthNight * nightRainAmbientColor) * rainNightWeight);

        vec3 lightColor   = mix(clearLightColor, rainLightColor, rainFactor);
        vec3 ambientColor = mix(clearAmbientColor, rainAmbientColor, rainFactor);
    #elif defined NETHER
        vec3 lightColor   = vec3(0.0);
        vec3 ambientColor = (netherColor + 0.5 * lavaLightColor) * (0.9 + 0.45 * vsBrightness);
    #elif defined END
        vec3 endLightColor = vec3(0.68, 0.51, 1.07);
        vec3 endOrangeCol = vec3(1.0, 0.3, 0.0);
        float endLightBalancer = 0.2 * vsBrightness;
        vec3 lightColor    = endLightColor * (0.35 - endLightBalancer);
        vec3 ambientColor  = endLightColor * (0.2 + endLightBalancer);
    #endif

#endif //INCLUDE_LIGHT_AND_AMBIENT_COLORS