# Asset Plan

Tracks art assets needed for the game, how to create them, and their status.

---

## Terrain Splatmap Textures

The splatmap shader maps zone types to tileable ground textures on the terrain mesh. Each biome needs its own set of textures so zones look distinct across Meadow, Canyon, and Desert.

### What's Needed

**5 core textures per biome** (15 total for the initial three biomes):

| Zone | Meadow | Canyon | Desert |
|------|--------|--------|--------|
| **Fairway** | Manicured grass with faint mow stripes | Dry yellow-green grass on packed earth | Short sandy turf, sparse |
| **Green** | Very smooth, bright putting green | Slightly greener patch on brown ground | Small oasis-green patch |
| **Rough** | Tall wild grass, weeds, uneven | Rocky scrubland, sparse dry brush | Sand with scattered dead scrub |
| **Bunker** | Light tan sand, fine grain | Red/orange coarse sand | Fine golden sand, smooth |
| **Slope/Cliff** | Exposed brown earth, dirt cross-section | Layered red-brown sandstone, rock strata | Compacted dark sand, cracked hardpan |

**Reuse rules** (skip these to start):
- **Tee** — reuse Fairway texture (or a slightly lighter variant)
- **OOB** — reuse Rough texture
- **Water/Lava** — rendered as separate planes, not part of the terrain splatmap

### Texture Specs

| Property | Value | Notes |
|----------|-------|-------|
| **Size** | 256x256 or 512x512 | 256 is fine for stylized; 512 for more detail |
| **Format** | PNG | Godot imports and compresses automatically |
| **Tileable** | Yes — seamless edges | Most important quality |
| **Perspective** | Top-down | Ground viewed from golf camera angle |
| **Style** | Hand-painted / stylized | Match the low-poly vertex-color look, not photorealistic |
| **Channels** | RGB albedo only (first pass) | Normal + roughness maps are a future enhancement |

### File Naming & Location

```
resources/textures/terrain/
    meadow_fairway.png
    meadow_green.png
    meadow_rough.png
    meadow_bunker.png
    meadow_slope.png

    canyon_fairway.png
    canyon_green.png
    canyon_rough.png
    canyon_bunker.png
    canyon_slope.png

    desert_fairway.png
    desert_green.png
    desert_rough.png
    desert_bunker.png
    desert_slope.png
```

---

## Creating Textures in GIMP / Aseprite

### General Workflow

1. **Start with a flat base color** that matches the existing vertex color for that zone (reference the biome factory methods in `biome_definition.gd` or look at the game in-engine)
2. **Add subtle variation** — noise, brushwork, or pattern on top of the base
3. **Make it tile** — use the tiling tools to ensure seamless edges
4. **Keep it simple** — these are viewed from a distance at camera height; fine detail won't read. Bold color variation and value contrast matter more than detail

### GIMP — Step by Step

**Setting up a tileable texture:**
1. Create a new image at 256x256 (or 512x512)
2. Fill with the base zone color
3. `Filters → Noise → HSV Noise` — add subtle color variation (keep values low: 2-5 for hue/saturation, 10-20 for value)
4. Paint details with a soft brush at low opacity (grass blades, sand grain variation, dirt patches)
5. **Make seamless**: `Filters → Map → Tile Seamless` — this blends the edges so the texture tiles without visible seams
6. Check the tiling: `Filters → Map → Tile` to preview a 3x3 grid and spot any obvious repeats
7. Export as PNG

**Grass textures (fairway, green, rough):**
- Base: the zone's green color
- Use a small hard brush with slight color variation to dab grass blade clusters
- For fairway: add faint horizontal or diagonal stripes (alternating slightly lighter/darker bands) to suggest mow lines — use a large soft brush at 5-10% opacity
- For rough: use a larger, more scattered brush pattern with yellow-brown mixed in
- For green: keep it very smooth — minimal variation, just subtle noise

**Sand textures (bunker):**
- Base: the zone's tan/sand color
- `Filters → Noise → HSV Noise` with moderate value noise (20-30)
- Optionally add a few tiny dark speckles for grain

**Dirt/rock textures (slope, rough):**
- Base: the slope color from `biome_definition.gd`
- Add darker cracks or lines for rock strata (canyon) or root lines (meadow)
- Use `Filters → Distort → Spread` lightly to break up any too-regular patterns

### Aseprite — Step by Step

Aseprite works well for a more pixel-art / stylized approach at smaller resolutions (64x64 or 128x128, then scale up).

1. Create a new sprite at 64x64 or 128x128
2. Fill with the base color
3. Use the pencil tool with a custom brush (scatter dots, small dashes) to add variation
4. For grass: alternate 2-3 shades of green in a dithered or stippled pattern
5. For sand: stipple 2-3 warm tans
6. **Tiling**: Aseprite has `Edit → Preferences → Tiled Mode` — enable this and paint. Strokes wrap across edges, making seamless textures easy
7. Export as PNG, then scale up to 256x256 in Godot's import settings (set filter to "Nearest" for crisp pixels, or "Linear" for smoother blending)

### Color Reference

Use these as starting base colors (from the existing vertex colors in `biome_definition.gd`):

**Meadow:**
| Zone | RGB | Hex | Swatch |
|------|-----|-----|--------|
| Fairway | (51, 140, 38) | `#338C26` | Dark green |
| Green | (38, 166, 38) | `#26A626` | Bright green |
| Rough | (77, 122, 31) | `#4D7A1F` | Olive green |
| Bunker | (217, 199, 128) | `#D9C780` | Light tan |
| Slope | (115, 89, 64) | `#735940` | Warm brown |

**Canyon:**
| Zone | RGB | Hex | Swatch |
|------|-----|-----|--------|
| Fairway | (140, 107, 71) | `#8C6B47` | Dusty brown |
| Green | (115, 133, 77) | `#73854D` | Muted olive |
| Rough | (128, 97, 56) | `#806138` | Tan brown |
| Bunker | (191, 153, 89) | `#BF9959` | Sandy gold |
| Slope | (140, 77, 51) | `#8C4D33` | Red-brown |

**Desert:**
| Zone | RGB | Hex | Swatch |
|------|-----|-----|--------|
| Fairway | (209, 184, 115) | `#D1B873` | Warm sand |
| Green | (102, 140, 64) | `#668C40` | Oasis green |
| Rough | (199, 166, 97) | `#C7A661` | Dry tan |
| Bunker | (230, 209, 140) | `#E6D18C` | Pale sand |
| Slope | (128, 102, 71) | `#806647` | Dark tan |

---

## Fallback: Downloading Textures

If hand-painting isn't producing the right look, these free CC0 sources have tileable ground textures:

- **ambientCG.com** — search "Ground Grass", "Sand", "Rock Ground", "Dirt". Download the 1K or 2K albedo PNG, then scale down to 512x512 in GIMP
- **Polyhaven.com/textures** — similar search terms, CC0 PBR sets
- **Kenney.nl/assets** — stylized/low-poly texture packs that may match the game's art direction better than photorealistic options

When downloading, grab just the albedo/diffuse map for now. Tint it in GIMP (`Colors → Hue-Saturation` or `Colors → Color Balance`) to match the biome's color palette above.

---

## Status

| Asset Set | Status |
|-----------|--------|
| Meadow terrain textures (5) | Not started |
| Canyon terrain textures (5) | Not started |
| Desert terrain textures (5) | Not started |
| Splatmap shader | Not started (waiting on textures) |

---

## Future Assets

Space reserved for assets needed by upcoming features:

- **Tree/foliage models** — currently simple cone + cylinder meshes
- **Obstacle models** — rocks, cacti, ruins per biome
- **Ball trail / action VFX** — particle textures for ball actions (jump, boost, brake)
- **UI icons** — upgrade card icons, action bar icons
- **Skybox textures** — per-biome sky (currently procedural environment)
