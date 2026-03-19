# Procedural Terrain Generation System — Design & Status

## Context

The terrain system generates rolling hills, water/lava hazards, biome-specific mechanics, and proper golf course structure (fairway, rough, green, bunkers) — all procedurally from a seed. Each hole gets its own heightmap, zone map, obstacles, and wind.

Inspired by Mario Golf: Super Rush's biome progression (Meadow → Canyon → Desert → Storm Forest → Volcanic), where each biome introduces new mechanics, not just visuals.

---

## Architecture Overview

Three layers, following "pure data first, scene building second":

```
BiomeDefinition (Resource)     ← rules, colors, noise params, hazards, wind per biome
        |
HeightmapGenerator (static)    ← produces TerrainData from noise + hole routing
        |
TerrainMeshBuilder (static)    ← converts TerrainData into ArrayMesh + collision shape
```

The central data structure is **TerrainData** — a grid-based heightmap + zone map queried by: physics, trajectory preview, mesh building, obstacle placement, hazard detection.

---

## Biome System

### Biome Types

| Biome | Theme | Key Features | New Mechanic | Status |
|-------|-------|-------------|--------------|--------|
| **Meadow** | Classic golf, gentle hills | Wide fairways, mild slopes, light bunkers, water ponds | Baseline — light wind | Implemented |
| **Canyon** | Ridges, mesas, cliffs | Dramatic elevation, narrow bridges, water below | Moderate wind, deep water | Implemented |
| **Desert** | Dunes, sand, arid | Sand waste areas, wide bunkers, high friction | Strong variable wind | Implemented |
| **Storm Forest** | Dense trees, rain | Narrow corridors, tall canopy, mud patches | Rain reduces roll, wind gusts | Future |
| **Volcanic** | Lava, dark rock, crags | Lava pits, sharp elevation, rock walls | Lava hazards, hard rocky bounces | Future |
| **Urban** | Rooftops, concrete | Flat elevated platforms, gap jumps, walls | Hard surfaces (extreme bounce/roll) | Future |

### BiomeDefinition Resource (`resources/biome_definition.gd`)

Each biome is a `@tool` Resource with exported parameters, auto-populating 8 ZoneDefinitions on creation:

**Terrain Noise:**
- `terrain_amplitude` (0–20m), `terrain_frequency` (0.001–0.1)
- `noise_octaves` (1–8), `noise_lacunarity` (1–4), `noise_gain` (0–1)

**Elevation:**
- `min_height`, `max_height` — clamp range after all generation passes

**Fairway Shaping:**
- `fairway_flatten_strength` (0–1) — how aggressively fairway blends to spine height
- `green_flatten_radius`, `tee_flatten_radius` — circular flattening radii

**Hazards:**
- `water_height` — height below which terrain becomes water (-999 = disabled)
- `lava_height` — height below which terrain becomes lava (-999 = disabled)

**Wind:**
- `base_wind_strength` (m/s) — average wind speed per hole
- `wind_variance` — random ± range around base strength

**Rendering:**
- `material_override: Material` — optional drop-in for textured terrain (splatmap future)
- `uv_scale` — world-space UV tiling density (mesh always generates UVs)

**Factory methods:** `create_meadow()`, `create_canyon()`, `create_desert()` — each with biome-appropriate defaults.

**Saved .tres files:** `resources/biomes/meadow.tres`, `canyon.tres`, `desert.tres`

### ZoneDefinition Resource (`resources/zone_definition.gd`)

Per-zone configurable properties within a biome:

- `zone_type` (enum: Fairway, Rough, Green, Tee, Bunker, Water, Lava, OOB)
- `color: Color` — vertex color for terrain mesh
- `friction` (0–10) — ground friction multiplier
- `bounce_modifier` (0–3) — bounce multiplier
- **Terrain shaping:** `hill_scale`, `valley_scale` (amplitude), `hill_shape`, `valley_shape` (exponent: < 1 = rounded, > 1 = peaked), `height_offset` (constant shift, e.g. bunkers = -0.3)
- `texture: Texture2D` — for future splatmap shader

### BiomeSegment Resource (`resources/biome_segment.gd`)

Pairs a BiomeDefinition with course sequencing info:
- `biome: BiomeDefinition`
- `hole_count: int` (1–18)
- `cell_size` (0.5–8m) — terrain grid resolution
- `margin` (10–100m) — terrain bounds beyond playable area

### Biome Progression & Course Sequencing

Configured via `CourseManager.biome_sequence: Array[BiomeSegment]` in the Inspector:

```
biome_sequence:
  [0]: BiomeSegment { biome: Meadow,  hole_count: 3, cell_size: 2.0, margin: 30.0 }
  [1]: BiomeSegment { biome: Canyon,  hole_count: 3, cell_size: 2.5, margin: 35.0 }
  [2]: BiomeSegment { biome: Desert,  hole_count: 3, cell_size: 2.0, margin: 35.0 }
  → 9-hole course: holes 1–3 = Meadow, 4–6 = Canyon, 7–9 = Desert
```

- Total holes = sum of all `hole_count` values (derived, not separately configured)
- When `biome_sequence` is empty, falls back to 9 holes of default Meadow
- `HoleGenConfig` controls difficulty parameters (par ranges, fairway width, obstacle density) shared across all segments

**Run-based escalation (future):** A run manager could build `biome_sequence` dynamically: Run 1 = [Meadow×9], Run 2 = [Meadow×5, Canyon×4], Run 3 = [Meadow×3, Canyon×3, Desert×3].

---

## Terrain Generation Pipeline

Called from `HoleGenerator.generate()`, seven steps. Zone painting is done first (XZ spatial rules only), enabling per-zone height modifiers in step 3. Hazard zones are assigned last (need final heights).

### Step 1: Zone Painting (`_paint_zones`)
Assign each cell a zone type based on XZ proximity:

| Zone | Rule |
|------|------|
| GREEN | Within `green_flatten_radius` of cup |
| TEE | Within 3m of tee |
| FAIRWAY | Within `fairway_width / 2` of spine |
| ROUGH | All other cells |

Bunker zones are set by obstacle placement (separate from this grid pass).

### Step 2: Heightmap Generation (`_fill_noise`)
- Configure `FastNoiseLite` from biome noise params + seeded RNG
- Sample noise for each cell: `ground_height + noise * amplitude`

### Step 3: Per-Zone Height Modifiers (`_apply_zone_height_modifiers`)
For each cell, look up the zone's `ZoneDefinition` and reshape:
```gdscript
if delta > 0:
    delta = pow(delta, zone_def.hill_shape) * zone_def.hill_scale
else:
    delta = -pow(abs(delta), zone_def.valley_shape) * zone_def.valley_scale
height = ground_height + delta + zone_def.height_offset
```

### Step 4: Fairway Carving (`_carve_fairway`)
- Blend cells near the fairway spine toward spine elevation using `fairway_flatten_strength`
- Quadratic falloff: centre = full flattening, edges blend into rough

### Step 5: Green/Tee Flattening (`_flatten_area`)
- Flatten circular areas around cup and tee
- Quadratic falloff: centre snaps to `ground_height`, edges blend

### Step 6: Height Clamping (`_clamp_heights`)
- Clamp all cells to `biome.min_height` / `biome.max_height`

### Step 7: Hazard Zone Painting (`_paint_hazard_zones`)
- Reassign ROUGH and OOB cells below `water_height` to WATER zone
- Reassign ROUGH and OOB cells below `lava_height` to LAVA zone (takes priority)
- Spatial zones (GREEN, TEE, FAIRWAY) are never overridden

### Wind Generation (in HoleGenerator, not HeightmapGenerator)
- Roll random direction (angle) + strength from shared course RNG
- Strength = `biome.base_wind_strength + randf_range(-variance, variance)`, clamped ≥ 0
- Stored as horizontal `Vector3` on `HoleLayout.wind`

### Obstacle Placement (in HoleGenerator)
- Trees along fairway sides (density from `HoleGenConfig.tree_density`)
- Bunkers near green + fairway bunkers for par 4+ (density from `HoleGenConfig.bunker_density`)
- All obstacles placed at terrain surface height via `terrain_data.get_height_at()`

---

## TerrainData — The Central Data Structure

```
TerrainData (RefCounted)
├── heights: PackedFloat32Array    # grid-based heightmap (row-major)
├── zones: PackedByteArray         # zone type per cell (ZoneType enum)
├── grid_width, grid_depth, cell_size, origin
├── tee_position, cup_position: Vector3 (with correct Y)
├── fairway_spine: Array[Vector3]
├── water_height, lava_height: float  # -999 = disabled
├── biome: RefCounted (BiomeDefinition)  # for friction/color lookups
│
├── get_height_at(x, z) → float         # bilinear interpolation
├── get_normal_at(x, z) → Vector3       # from height gradient
├── get_zone_at(x, z) → ZoneType        # nearest cell lookup
├── get_friction_at(x, z) → float       # zone-based via biome
├── is_water_at(x, z) → bool            # height < water_height
└── is_lava_at(x, z) → bool             # height < lava_height
```

Pre-computed grid (not real-time noise sampling) because generation applies fairway carving + flattening that can't be expressed as pure noise. Bilinear interpolation of a grid is faster than multi-octave noise per physics frame. ~30KB per hole.

---

## Terrain Mesh Building

`TerrainMeshBuilder` converts TerrainData into renderable geometry:

1. **ArrayMesh via SurfaceTool** — two triangles per grid cell, standard heightmap triangulation
2. **Vertex colors** per vertex from zone type (using biome's color palette via `BiomeDefinition.get_color()`)
3. **UV coordinates** on every vertex (`world_xz * uv_scale`) for future textured rendering
4. **Normals** auto-generated by SurfaceTool
5. **ConcavePolygonShape3D** from the same triangles for collision

Single MeshInstance3D + StaticBody3D per hole. Material from `BiomeDefinition.material_override` if set, otherwise vertex-color unshaded.

### Hazard Planes (ProceduralHole)
- **Water plane**: semi-transparent blue PlaneMesh at `water_height + 0.05`, double-sided, unshaded
- **Lava plane**: semi-transparent emissive orange/red PlaneMesh at `lava_height + 0.05`
- Both cover full terrain grid extents, rendered by `ProceduralHole._build_hazard_planes()`

### Textured Terrain Rendering (Future)

**Mechanism 1: Simple material override** — set `material_override` on BiomeDefinition to any `StandardMaterial3D` with an albedo texture. UVs are already generated.

**Mechanism 2: Splatmap shader (per-zone textures)** — for distinct materials per zone (grass fairway, sand bunker, rock rough):
1. Bake `TerrainData.zones` into an `ImageTexture` (zone map)
2. Shader samples zone map + per-zone albedo textures, blends at boundaries
3. `ZoneDefinition.texture` feeds per-zone texture uniforms
4. Vertex colors preserved for optional tinting

---

## Physics

### Ground Detection
- `terrain.get_height_at(pos.x, pos.z)` per frame (bilinear interpolation)
- `terrain.get_normal_at(pos.x, pos.z)` for slope physics

### Slope Physics
- Gravity projected onto slope surface → ball rolls downhill naturally
- Friction applied along slope surface

### Zone Friction
- Per-frame lookup via `terrain.get_friction_at(pos.x, pos.z)` → `biome.get_friction(zone_type)`
- Each biome defines per-zone friction: GREEN ~0.7, FAIRWAY 1.0, ROUGH 1.5–2.0, BUNKER 3.0–4.0

### Wind
- Applied as `velocity += wind * delta` while ball is airborne (before damping)
- Longer flights accumulate more drift
- Trajectory preview automatically curves to show wind effect

### Hazard Detection
- **Water**: checked when ball comes to rest via `is_water_at()`. Teleports back to `last_shot_position`, emits `hit_water` → +1 penalty stroke.
- **Lava**: checked every frame while ball is on ground via `is_lava_at()`. Bounces ball upward + toward last shot position. Max 3 bounces before force-teleport. Emits `hit_lava` on first contact → +1 penalty stroke.

### Hazard Mitigation (Future — Phase 9)
Both hazards are designed to be mitigable via roguelike upgrades:
- "Stone Skipper" → ball skips across water (N bounces before sinking)
- "Heat Rising" → ball floats over lava on convection

---

## Wind System

Per-hole wind is generated deterministically from the course seed:

- `BiomeDefinition` exports `base_wind_strength` and `wind_variance`
- `HoleGenerator.generate()` rolls direction (random angle) + strength per hole
- Stored as `HoleLayout.wind: Vector3` (horizontal only)
- `GolfBall.set_wind()` passes wind to `PhysicsParams.wind`
- **WindIndicator** (`scripts/ui/wind_indicator.gd`) — HUD element with rotatable arrow, speed in m/s, compass direction. Hidden when calm.

| Biome | Base Strength | Variance | Feel |
|-------|:------------:|:--------:|------|
| Meadow | 1.0 m/s | ±1.5 | Light breeze, some calm holes |
| Canyon | 2.5 m/s | ±2.0 | Moderate, noticeable drift |
| Desert | 4.0 m/s | ±3.0 | Strong, must account for it |

---

## File Structure

```
scripts/terrain/
    terrain_data.gd              # TerrainData (heightmap + zones + queries)
    heightmap_generator.gd       # Static: noise → routing-carved heightmap
    terrain_mesh_builder.gd      # Static: TerrainData → ArrayMesh + collision

scripts/ui/
    wind_indicator.gd            # Wind direction + speed HUD element

resources/
    zone_definition.gd           # ZoneDefinition resource (per-zone properties)
    biome_definition.gd          # BiomeDefinition resource (biome-level params)
    biome_segment.gd             # BiomeSegment resource (biome + hole_count)
    biomes/
        meadow.tres              # Gentle terrain, light wind, water at 0.0
        canyon.tres              # Dramatic elevation, moderate wind, water at -0.5
        desert.tres              # Sandy dunes, strong wind, no water/lava

scripts/
    hole_generator.gd            # HoleLayout generation (obstacles, wind, terrain)
    hole_gen_config.gd           # Difficulty params (par, fairway width, densities)
    procedural_hole.gd           # Scene builder (terrain mesh, obstacles, cup, hazard planes)

    managers/
        course_manager.gd        # Biome sequencing, hole progression
        scoring_manager.gd       # Stroke counting + penalty strokes
```

---

## Implementation Phases

| Phase | What | Status |
|-------|------|--------|
| **1** | TerrainData + HeightmapGenerator (flat output) | **Complete** |
| **2** | TerrainMeshBuilder + collision | **Complete** |
| **3** | Terrain-aware PhysicsSimulator (slopes, normals) | **Complete** |
| **4** | Zone friction + BiomeDefinition/ZoneDefinition/BiomeSegment resources + multi-biome courses | **Complete** |
| **5** | Water/lava hazards + hazard plane rendering + penalty strokes | **Complete** |
| **6** | Terrain textures (splatmap shader) + run-based biome progression | **Partial** — .tres biomes done, shader & run manager deferred |
| **7** | Wind mechanics + wind UI | **Complete** |
| **8** | Dynamic/timed hazards (geysers, boulders, lightning) | Planned |
| **9** | Hazard mitigation upgrades (Stone Skipper, Heat Rising) | Planned |
| **10** | Advanced routing (doglegs, island greens) | Planned |

Each phase is independently testable and the game stays playable throughout.

---

## Resolved Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Hazard behavior** | Hybrid: water = penalty+teleport, lava = bounce-out | Both upgradable (stone skip, heat float) |
| **Biome progression** | Editor-configured BiomeSegment array | Flexible for designers; run manager can build dynamically later |
| **Wind model** | Constant per-hole, varies between holes | Simple, predictable for players; per-biome base+variance gives progression |
| **Terrain resolution** | 2m cells (~7.5K tris) | Good balance of detail vs performance |
| **Zone properties** | Editor-configurable ZoneDefinition resources per biome | Designers tweak friction/color/shaping in Inspector |
| **Terrain rendering** | Vertex colors now, splatmap shader later | material_override slot enables drop-in texture support when ready |
| **Wind UI** | Arrow + speed + compass direction, hidden when calm | Non-intrusive, provides all info needed to aim |

---

## Future Work

### Phase 8: Dynamic/Timed Hazards
Per-biome hazards escalating with difficulty:
- **Meadow**: None (pure golf)
- **Canyon**: Periodic rock slides
- **Desert**: Sand geysers on timer
- **Storm Forest**: Lightning strikes
- **Volcanic**: Rolling boulders, lava geysers
- **Urban**: Timed barriers/gates

Density configurable via `BiomeDefinition` exports:
```gdscript
@export_range(0.0, 3.0) var dynamic_hazard_density: float = 1.0
```

### Phase 9: Hazard Mitigation Upgrades
New `UpgradeEffect` stat entries:
- `WATER_SKIP` → ball skips across water N times
- `LAVA_RESIST` → reduced gravity near lava surface
- Future: reduce penalty strokes, increase skip count

### Phase 10: Advanced Routing
- Dogleg waypoints (1–2 turn points for par 4–5)
- Island greens surrounded by water/lava
- Multi-spine fairway routing

### Splatmap Shader (Phase 6 remainder)
Zone map texture → shader with per-zone albedo/normal/roughness. Infrastructure ready (UVs, material_override slot, ZoneDefinition.texture). Needs texture assets.

### Run-Based Progression (Phase 6 remainder)
Run manager builds `biome_sequence` dynamically based on meta progression level. Each run introduces one new biome.
