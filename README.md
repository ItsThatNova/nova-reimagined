# Nova Reimagined

**A modified Minecraft shader pack based on Complementary Reimagined by EminGT.**

Nova Reimagined extends Complementary Reimagined with a shader-driven surface snow system and a curated set of defaults tuned for a stylised, painterly aesthetic. It is designed to complement Minecraft's visual identity rather than replace it.

---

## Features

### Surface Snow System
Nova Reimagined's centrepiece feature. Snow is painted directly onto terrain, paths, foliage, wood, and structural blocks in snowy biomes using a noise-driven pixel-locked pattern. Coverage fades naturally under tree canopies and near light sources, creating organic melt patterns rather than hard biome boundary lines. Up to four snow texture variants are resolved automatically from your active resource pack stack, so the snow appearance adapts to whatever resource pack you have installed. Requires the Nova Reimagined Snow companion mod.

### Cell Shaded Lighting
An optional cel-shaded lighting model that quantises block light into discrete bands, giving illuminated areas a stylised, hand-drawn quality. Band count, contrast, and ambient contribution are all tunable, making it possible to dial in anything from a subtle painterly warmth to a more pronounced cartoon look. Works alongside coloured lighting for fully coloured cel-shaded block light.

### Extended Dark Outline System
A configurable dark outline pass that traces the edges of geometry, reinforcing Minecraft's natural block silhouettes. Outline weight, fade distance, and fade range are all adjustable, letting you control how aggressively outlines appear at distance. Can be combined with the cel-shaded lighting for a cohesive illustrative style.

### Per-Time-of-Day Weather Visuals
Rain and storm conditions have fully independent visual profiles for day, dusk, and night. Ambient levels, light intensity, atmospheric fog, border fog brightness, cloud brightness, light warmth, and glare desaturation are all separately tunable across all six weather and time-of-day combinations. This allows storms to feel dramatically different depending on when they hit rather than applying a single flat weather filter over everything.

### Underwater Visuals
Underwater environments have dedicated colour and brightness controls for day, dusk, and night, along with independent settings for water fog, border fog, and light shafts. Water colour, foam intensity, texture detail, and refraction are all configurable, giving full control over how water looks from both above and below the surface.

### SMAA Anti-Aliasing
Subpixel Morphological Anti-Aliasing is available alongside TAA, providing sharp edge smoothing with less ghosting on moving geometry than temporal methods alone. SMAA and TAA can be used in combination or independently depending on your preference for sharpness versus stability.

### Alternative Tone Mappers
In addition to the native Complementary tonemapper, Nova Reimagined includes a selection of alternative tonemapping operators. Each operator changes how colour and brightness are mapped to the display, giving meaningfully different looks ranging from filmic contrast curves to flatter, more neutral presentations. The native tonemapper's brightness, contrast, saturation, and vibrance controls remain available regardless of which operator is selected.

---

## Credits

Nova Reimagined is built on top of Complementary Reimagined by EminGT.
Original pack and full credits: https://www.complementary.dev

- **EminGT** - Developer of Complementary Reimagined, the base this pack is built upon
- **Capt Tatsu** - Developer of BSL Shaders, whose generosity made Complementary possible
- **ItsThatNova** - Nova Reimagined modifications and the companion Nova Reimagined Snow mod

---

## Requirements

- Minecraft 1.21.x (Java Edition)
- [Iris Shaders](https://modrinth.com/mod/iris) 1.6+
- [Nova Reimagined Snow](https://github.com/ItsThatNova/nova-reimagined-snow) companion mod (required for the snow system)
- [Distant Horizons](https://modrinth.com/mod/distanthorizons) (optional, fully supported)

---

## Installation

1. Install Iris Shaders
2. Install the Nova Reimagined Snow companion mod
3. Place the Nova Reimagined shader pack zip in your shaderpacks folder
4. Select it in Iris settings
5. Enable surface snow toggles under **Shader Settings > Other > Surface Snow**

---

## Surface Snow Settings

Snow coverage settings are found under **Shader Settings > Other > Surface Snow**:

- **Pixel Size** - Controls the cell size and coverage step count of the snow noise pattern
- **Accent Max Snow Coverage** - Sets the maximum snow opacity on path and accent blocks
- **Accent Melt Patch Scale** - Controls the scale of melt patches on accent blocks

---

## License

This pack is distributed under the Complementary License Agreement 1.6.
See `License.txt` for full terms.

Nova Reimagined credits Complementary Reimagined as its Original Pack per section 1.3 of that agreement.
