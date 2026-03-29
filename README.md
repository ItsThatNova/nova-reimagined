# Nova Reimagined

**A modified Minecraft shader pack based on Complementary Reimagined by EminGT.**

Nova Reimagined extends Complementary Reimagined with a shader-driven surface snow system that paints snow directly onto terrain, paths, foliage, wood, and structural blocks in snowy biomes. Snow coverage, patch scale, and per-surface intensity are all configurable from the shader settings menu.

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
- [Nova Reimagined Snow](https://github.com/ItsThatNova) companion mod (required for the snow system)
- [Distant Horizons](https://modrinth.com/mod/distanthorizons) (optional, fully supported)

---

## Installation

1. Install Iris Shaders
2. Install the Nova Reimagined Snow companion mod
3. Place the Nova Reimagined shader pack zip in your shaderpacks folder
4. Select it in Iris settings
5. Enable surface snow toggles under **Shader Settings > Other > Surface Snow**

---

## Surface Snow System

The snow system requires the Nova Reimagined Snow companion mod to function. Without it the shader falls back to the vanilla `inSnowy` uniform, which causes snow tinting to bleed across biome borders.

With the mod installed, snow draws accurately at biome boundaries and fades naturally under tree canopies and near light sources. Up to four snow texture variants are resolved automatically from your active resource pack stack, so snow appearance adapts to whatever resource pack you have installed.

Snow coverage settings are found under **Shader Settings > Other > Surface Snow**:

- **Pixel Size** - Controls the cell size and coverage step count of the snow noise pattern
- **Accent Max Snow Coverage** - Sets the maximum snow opacity on path and accent blocks
- **Accent Melt Patch Scale** - Controls the scale of melt patches on accent blocks

---

## License

This pack is distributed under the Complementary License Agreement 1.6.
See `License.txt` for full terms.

Nova Reimagined credits Complementary Reimagined as its Original Pack per section 1.3 of that agreement.
