# Terrain Generation — Technical Reference

How the procedural terrain system works, end to end. This document describes the **implemented** behavior as of the current codebase — not planned/future features. Updated alongside each terrain generation plan phase.

---

## Pipeline Overview

```
CourseManager.generate_course(seed)
  │  Creates one RandomNumberGenerator seeded once for the entire course.
  │  Iterates biome_sequence (Array[BiomeSegment]) to generate all holes.
  │
  └─► HoleGenerator.generate(rng, hole_number, par, config, biome, cell_size, margin)
        │  Consumes RNG draws in strict order for determinism.
        │  Produces a HoleLayout containing everything needed to build the hole.
        │
        ├─ 1. Hole routing       (direction, length, fairway width — par-scaled)
        ├─ 2. Cup position       (derived from direction + length)
        ├─ 3. Terrain generation  → HeightmapGenerator.generate(...)
        │     └─ Produces TerrainData (heightmap + zone map)
        ├─ 4. Obstacle placement  (trees, bunkers — sub-RNG isolated)
        ├─ 5. Dynamic hazards     (rock slides, geysers — sub-RNG isolated)
        ├─ 6. Wind generation     (direction + strength from biome params)
        │
        └─► HoleLayout { routing, terrain_data, obstacles, dynamic_hazards, wind }
              │
              └─► ProceduralHole.build(layout)
                    ├─ TerrainMeshBuilder.build(terrain_data)
                    │   └─ ArrayMesh (vertex-colored) + ConcavePolygonShape3D
                    ├─ Hazard planes (water/lava translucent surfaces)
                    ├─ Obstacles (trees with collision, bunker discs)
                    ├─ Dynamic hazards (RockSlideHazard / SandGeyserHazard)
                    └─ Cup (Area3D + flag visual)
```

---

## Key Data Structures

### TerrainData (`scripts/terrain/terrain_data.gd`)

Grid-based heightmap + zone map for a single hole. Generated once, queried at runtime by physics, trajectory preview, and mesh building.

| Field | Type | Description |
|-------|------|-------------|
| `heights` | `PackedFloat32Array` | Row-major heightmap (`x + z * grid_width`) |
| `zones` | `PackedByteArray` | Zone type per cell (same layout as heights) |
| `grid_width`, `grid_depth` | `int` | Grid dimensions in cells |
| `cell_size` | `float` | Meters per cell (default 2.0) |
| `origin` | `Vector3` | World-space position of grid corner (0,0) |
| `biome` | `BiomeDefinition` | Reference for friction/color lookups at runtime |
| `fairway_spine` | `Array[Vector3]` | Waypoints from tee to cup |
| `tee_position`, `cup_position` | `Vector3` | With correct Y from heightmap |
| `water_height`, `lava_height` | `float` | -999.0 = disabled |

**ZoneType enum:** `FAIRWAY=0, ROUGH=1, GREEN=2, TEE=3, BUNKER=4, WATER=5, LAVA=6, OOB=7`

**Query methods:**

| Method | Returns | Algorithm |
|--------|---------|-----------|
| `get_height_at(x, z)` | `float` | Bilinear interpolation of 4 nearest cell corners |
| `get_normal_at(x, z)` | `Vector3` | Cross product of tangent vectors from height gradient, sampled at ±`cell_size` |
| `get_zone_at(x, z)` | `int` | Nearest-cell lookup (no interpolation) |
| `get_friction_at(x, z)` | `float` | Zone lookup → `biome.get_friction(zone)`, fallback 1.0 |
| `is_water_at(x, z)` | `bool` | `get_height_at() < water_height` (and water enabled) |
| `is_lava_at(x, z)` | `bool` | `get_height_at() < lava_height` (and lava enabled) |

Memory: ~30KB per hole (`heights` + `zones` for a typical grid).

### HoleLayout (`scripts/hole_generator.gd`)

Output of `HoleGenerator.generate()`, consumed by `ProceduralHole.build()`.

| Field | Type | Description |
|-------|------|-------------|
| `hole_number`, `par` | `int` | Hole index (1-based) and par |
| `tee_position` | `Vector3` | Always `(0, 0, 0)` — scene root is tee |
| `cup_position` | `Vector3` | World offset from tee |
| `hole_direction` | `float` | Radians from north (0 = straight ahead) |
| `hole_length` | `float` | Tee-to-cup distance in meters |
| `fairway_width` | `float` | Width of the playable corridor |
| `obstacles` | `Array[ObstacleDescriptor]` | Trees and bunkers |
| `dynamic_hazards` | `Array[DynamicHazardDescriptor]` | Rock slides, geysers |
| `terrain_data` | `TerrainData` | The heightmap for this hole |
| `wind` | `Vector3` | Horizontal wind vector |

### BiomeDefinition (`resources/biome_definition.gd`)

`@tool` Resource with exported parameters defining all visual and mechanical properties for a biome. Each biome has 8 ZoneDefinitions auto-populated on creation.

**Terrain noise:** `terrain_amplitude`, `terrain_frequency`, `noise_octaves`, `noise_lacunarity`, `noise_gain`

**Elevation:** `min_height`, `max_height`

**Plateaus:** `plateau_factor` (0-1 blend toward terraced), `plateau_levels` (number of bands)

**Fairway:** `fairway_flatten_strength`, `green_flatten_radius`, `tee_flatten_radius`

**Hazards:** `water_height`, `lava_height`, `dynamic_hazard_density`

**Wind:** `base_wind_strength`, `wind_variance`

**Slope rendering:** `slope_color`, `slope_threshold`, `slope_color_strength`

**Rendering:** `material_override`, `uv_scale`

**Factory methods:** `create_meadow()`, `create_canyon()`, `create_desert()` — populate all fields with tuned defaults. Saved .tres files live in `resources/biomes/`.

### ZoneDefinition (`resources/zone_definition.gd`)

Per-zone properties within a biome:

| Field | Type | Description |
|-------|------|-------------|
| `zone_type` | `int` | ZoneType enum value |
| `color` | `Color` | Vertex color for terrain mesh |
| `friction` | `float` | Ground friction multiplier (0.7 green, 1.0 fairway, 3.0+ bunker) |
| `bounce_modifier` | `float` | Bounce multiplier |
| `hill_scale`, `valley_scale` | `float` | Amplitude multipliers for terrain shaping |
| `hill_shape`, `valley_shape` | `float` | Exponents (<1 rounded, >1 peaked) |
| `height_offset` | `float` | Constant vertical shift (e.g. -0.3 for bunkers) |

### HoleGenConfig (`scripts/hole_gen_config.gd`)

Difficulty tuning resource attached to CourseManager:

| Field | Default | Description |
|-------|---------|-------------|
| `min_par`, `max_par` | 3, 5 | Par range |
| `length_multiplier` | 1.0 | Scales hole length |
| `fairway_width_scale` | 1.0 | Scales fairway width |
| `direction_variety` | 0.5 | How angled holes can be from straight ahead |
| `tree_density` | 1.0 | Tree pair frequency |
| `bunker_density` | 1.0 | Bunker placement frequency |

---

## Heightmap Generation Pipeline

`HeightmapGenerator.generate()` runs 7 steps sequentially. Each step reads and mutates the same TerrainData instance.

### Step 1: Grid Setup

Computes an axis-aligned bounding box around the rotated hole (tee→cup direction + margin), then divides into a grid at `cell_size` resolution. Initializes `heights` and `zones` arrays.

### Step 2: Zone Painting (`_paint_zones`)

Assigns zone types based purely on XZ spatial rules — no height dependency.

| Zone | Rule |
|------|------|
| GREEN | Within `green_flatten_radius` (default 8m) of cup position |
| TEE | Within 3m of tee position |
| FAIRWAY | Within `fairway_width / 2` of the tee→cup spine line |
| ROUGH | Everything else |

Bunker zones are assigned later by obstacle placement, not this grid pass.

### Step 3: Noise Fill (`_fill_noise`)

Configures `FastNoiseLite` (Simplex) from the biome's noise parameters, seeded by a value drawn from the course RNG.

```
height[i] = ground_height + noise.get_noise_2d(world_x, world_z) * terrain_amplitude
```

| Biome | Amplitude | Frequency | Octaves | Lacunarity | Gain |
|-------|-----------|-----------|---------|------------|------|
| Meadow | 3.0 | 0.012 | 3 | 2.0 | 0.5 |
| Canyon | 8.0 | 0.018 | 4 | 2.2 | 0.55 |
| Desert | 4.5 | 0.008 | 3 | 2.5 | 0.4 |

### Step 4: Per-Zone Height Modifiers (`_apply_zone_height_modifiers`)

Each zone's `ZoneDefinition` reshapes terrain amplitude differently:

```
delta = height - ground_height
if delta > 0:
    delta = pow(delta, hill_shape) * hill_scale
else:
    delta = -pow(abs(delta), valley_shape) * valley_scale
height = ground_height + delta + height_offset
```

This makes fairways smoother (low `hill_scale`), rough more dramatic, bunkers sunken (`height_offset = -0.3`), and water zones valley-like (`valley_scale = 1.5+`).

### Step 4b: Plateau Snapping (`_apply_plateaus`)

Optional step enabled when `biome.plateau_factor > 0`. Quantizes heights into discrete elevation bands, creating flat-topped mesas with steep transitions between them.

```
t = clamp((h - min_h) / (max_h - min_h), 0, 1)           # normalize to 0-1
terrace_t = round(t * levels) / levels                      # snap to nearest band
h = min_h + lerp(t, terrace_t, plateau_factor) * range     # blend toward snapped
```

| Biome | Factor | Levels | Effect |
|-------|--------|--------|--------|
| Meadow | 0.3 | 3 | Subtle, gentle rolling plateaus |
| Canyon | 0.6 | 4 | Strong mesa-like terracing |
| Desert | 0.4 | 3 | Moderate dune plateaus |

This step is critical for making slope coloring visible — it creates the steep cliff faces between terraces.

### Step 5: Fairway Carving (`_carve_fairway`)

Blends fairway cells toward the spine elevation so the path is playable:

```
distance = min distance to any spine segment (XZ plane)
if distance < fairway_width:
    target_height = spine height at nearest point
    blend = flatten_strength * (1 - (distance / fairway_width)^2)
    height = lerp(height, target_height, blend)
```

Quadratic falloff: center of fairway = full flattening, edges blend into rough. Biome controls `fairway_flatten_strength` (0.7-0.9).

### Step 6: Green/Tee Flattening (`_flatten_area`)

Circular flattening around green and tee positions:

```
distance = horizontal distance to center
if distance < radius:
    blend = 1 - (distance / radius)^2
    height = lerp(height, target_height, blend)
```

Green radius defaults to 8-12m, tee radius 5-6m. Ensures flat landing areas.

### Step 7: Height Clamping + Hazard Zone Painting

1. Clamp all heights to `[biome.min_height, biome.max_height]`
2. Reassign zones based on final heights:
   - ROUGH/OOB cells below `water_height` → WATER zone
   - ROUGH/OOB cells below `lava_height` → LAVA zone (takes priority over water)
   - Spatial zones (GREEN, TEE, FAIRWAY, BUNKER) are never overridden

---

## Mesh Building

`TerrainMeshBuilder.build(terrain_data)` converts the heightmap into renderable + collidable geometry.

### Geometry
- 2 triangles per grid cell (quad split along diagonal)
- Vertices positioned via `terrain.grid_to_world()` with heights
- ~7,500 triangles per hole at 2m cell size

### Vertex Colors
Each vertex gets a color from its zone's `ZoneDefinition.color` via the biome. Then slope coloring is applied:

```
steepness = 1 - normal.y                                    # 0=flat, 1=vertical
if steepness > slope_threshold:
    blend = clamp((steepness - threshold) / slope_range, 0, 1) * strength
    color = lerp(zone_color, slope_color, blend)
```

This makes steep cliff faces between plateaus render as rock/dirt rather than grass.

### UVs
World-space projection: `UV = (world_x, world_z) * uv_scale`. Ready for future splatmap textures.

### Collision
Same triangle data baked into a `ConcavePolygonShape3D`, attached to a `StaticBody3D` in the scene.

### Material
`create_material(biome)` returns either `biome.material_override` or a default `StandardMaterial3D` with `vertex_color_use_as_albedo = true`.

---

## Scene Building

`ProceduralHole.build(layout)` assembles the full 3D scene:

### Terrain
MeshInstance3D (from TerrainMeshBuilder) + StaticBody3D with collision shape.

### Hazard Planes
Flat `PlaneMesh` surfaces at water/lava height covering the full terrain grid.

| Type | Color | Properties |
|------|-------|------------|
| Water | `(0.1, 0.3, 0.65, 0.55)` | Transparent, unshaded, double-sided |
| Lava | `(0.9, 0.25, 0.02, 0.7)` | Transparent, unshaded, emissive (1.5x energy) |

### Trees
`StaticBody3D` with `CylinderShape3D` collision (full trunk+canopy height). Visuals: brown trunk cylinder + green foliage cone. Positioned at terrain height.

### Bunkers
Visual only — sand-colored `CylinderMesh` disc at terrain height. Friction penalty comes from zone-based physics lookup.

### Cup
`Area3D` with `CylinderShape3D` (radius 0.4m, height 0.4m). Detects ball entry via `body_entered` signal. Visuals: black cylinder hole + white pole + red flag.

### OOB Detection
Rotated AABB computed during terrain build. `is_out_of_bounds(world_pos)` checks if the ball has left the playable area.

---

## Dynamic Hazards

### State Machine (`DynamicHazardBase`)

All dynamic hazards cycle through three states on a deterministic timer:

```
IDLE ──► WARNING ──► ACTIVE ──► IDLE ──► ...
         │                      │
         └── collision disabled ┘── collision enabled
```

Timing is computed from accumulated elapsed time:
```
phase = fmod(elapsed + phase_offset, cycle_period)
idle_duration = cycle_period - active_duration - warning_duration
```

The `phase_offset` staggers multiple hazards so they don't all fire simultaneously.

The base class owns an `Area3D` with a `CylinderShape3D` (disabled during IDLE/WARNING, enabled during ACTIVE). When a ball enters the active zone, `hazard_activated(impulse)` is emitted.

### Rock Slides (`RockSlideHazard` — Canyon biome)

Boulders roll perpendicular to the fairway during the active phase.

**Placement:** 30-70% of hole length, perpendicular to fairway direction. Count: `int(hole_length / 50 * density)`, clamped 0-3.

**Timing:** 6-10s cycle, 2-3s active, 1.5s warning.

**Visuals:**
- IDLE: Orange warning strip (BoxMesh) oriented along slide direction
- WARNING: Strip pulses (color oscillation via `sin(time * 8)`)
- ACTIVE: 3 boulder SphereMeshes animate from -15m to +15m along slide direction

**Boulder animation:**
```
t = (active_time - boulder_offset) * boulder_speed / active_duration
position = slide_direction * lerp(-15, 15, t)
position.y = 0.8 + sin(t * 12) * 0.2      # rolling bob
rotate_x(delta * 4.0)                       # spin
```

Each boulder has slightly different speed (1.0, 1.15, 1.3) and stagger offset (0.0, 0.3, 0.6s).

**Collision:** Overrides base Area3D behavior. Instead of triggering on area entry, checks per-frame proximity to each boulder (`distance < 2.0m`). Each body can only be hit once per active cycle.

**Impulse:** `slide_direction * intensity + UP * intensity * 0.5`

### Sand Geysers (`SandGeyserHazard` — Desert biome)

Erupting sand columns that launch the ball upward.

**Placement:** 20-80% of hole length, offset ±40% of fairway width from center. Count: `int(hole_length / 60 * density)`, clamped 0-4.

**Timing:** 5-8s cycle, 1.5-2.5s active, 2s warning.

**Visuals:**
- IDLE: Dark sand disc (CylinderMesh), no particles
- WARNING: Disc pulses, light particles begin (12 particles, 2-4 m/s upward)
- ACTIVE: Full eruption (40 particles, 6-10 m/s), disc brightens

**Particles:** GPUParticles3D with ParticleProcessMaterial. Sphere emission at `effect_radius * 0.4`. Alpha curve fades in quickly, sustains, then fades out. Billboard quads, sand-colored.

**Collision:** Uses base Area3D behavior — triggers on area entry during ACTIVE state.

**Impulse:** `UP * intensity + away_from_center_normalized * intensity * 0.3`

---

## Hole Routing

`HoleGenerator.generate()` determines the shape of each hole.

### Direction
```
max_angle = (PI / 3.6) * config.direction_variety
direction = rng.randf_range(-max_angle, max_angle)
```

### Length (par-scaled)

| Par | Range (before multiplier) |
|-----|---------------------------|
| 3 | 60 – 100m |
| 4 | 120 – 160m |
| 5 | 180 – 240m |

### Fairway Width (par-scaled)

| Par | Range (before scale) |
|-----|----------------------|
| 3 | 10 – 16m |
| 4 | 14 – 22m |
| 5 | 18 – 28m |

### Obstacle Placement

**Trees:** One pair per 25 units of hole length (scaled by `tree_density`). Each pair places trees on alternating sides of the fairway at staggered distances (1.5-3x fairway width from center).

**Green bunkers:** 0-2 bunkers (scaled by `bunker_density`), placed 5-14m from cup at random angles. Radius 2-4m.

**Fairway bunker:** Par 4+ only. Placed at 30-60% of hole length, offset from fairway center. Radius 2.5-4.5m.

---

## Wind

Generated per hole from biome parameters:

```
angle = rng.randf() * TAU
strength = clamp(base_wind_strength + randf_range(-variance, variance), 0, ...)
wind = Vector3(cos(angle), 0, sin(angle)) * strength
```

| Biome | Base Strength | Variance | Typical Range |
|-------|:------------:|:--------:|:-------------:|
| Meadow | 1.0 m/s | ±1.5 | 0 – 2.5 |
| Canyon | 2.5 m/s | ±2.0 | 0.5 – 4.5 |
| Desert | 4.0 m/s | ±3.0 | 1.0 – 7.0 |

Applied as `velocity += wind * delta` while the ball is airborne.

---

## Determinism

The system is designed for multiplayer-safe deterministic generation.

### RNG Draw Order

One `RandomNumberGenerator` is created per course with `course_seed`. Draws happen in strict order:

```
Per hole (sequential):
  1. hole direction       — rng.randf_range()
  2. hole length          — rng.randf_range()
  3. fairway width        — rng.randf_range()
  4. noise seed           — rng.randi()           → HeightmapGenerator
  5. wind direction       — rng.randf()
  6. wind strength        — rng.randf_range()
  7. obstacle sub-seed    — rng.randi()            → isolated sub-RNG
  8. hazard sub-seed      — rng.randi()            → isolated sub-RNG
```

Obstacle and hazard placement use **sub-RNG derivation**: one draw from the parent RNG seeds a local `RandomNumberGenerator`. This isolates variable draw counts (different obstacle counts per hole) from affecting subsequent holes.

### Rules
- Never use global `randf()`/`randi()` in generation code
- Always consume from the shared `rng` parameter
- Fixed iteration order over all collections
- No generation logic in `_process` / `_physics_process`
- Document RNG draw count per function

---

## Biome Parameter Reference

### Meadow
| Parameter | Value | Effect |
|-----------|-------|--------|
| Amplitude | 3.0m | Gentle rolling hills |
| Frequency | 0.012 | Medium-sized features |
| Plateau factor | 0.3 / 3 levels | Subtle terracing |
| Fairway flatten | 0.85 | Smooth fairways |
| Water height | 0.0m | Ponds in low spots |
| Slope threshold | 0.3 | Moderate cliff coloring |
| Dynamic hazards | 0.0 | None |
| Wind | 1.0 ±1.5 m/s | Light breeze |

### Canyon
| Parameter | Value | Effect |
|-----------|-------|--------|
| Amplitude | 8.0m | Dramatic elevation |
| Frequency | 0.018 | Tighter features |
| Plateau factor | 0.6 / 4 levels | Strong mesa terracing |
| Fairway flatten | 0.7 | Less flattened — hillier fairways |
| Water height | -0.5m | Deep canyon water |
| Slope threshold | 0.25 | Aggressive cliff coloring |
| Dynamic hazards | 1.0 | Rock slides |
| Wind | 2.5 ±2.0 m/s | Moderate wind |

### Desert
| Parameter | Value | Effect |
|-----------|-------|--------|
| Amplitude | 4.5m | Moderate dunes |
| Frequency | 0.008 | Broad, sweeping features |
| Plateau factor | 0.4 / 3 levels | Moderate terracing |
| Fairway flatten | 0.9 | Smooth paths through dunes |
| Water height | -999 (disabled) | No water |
| Slope threshold | 0.35 | Gentle cliff coloring |
| Dynamic hazards | 1.5 | Sand geysers |
| Wind | 4.0 ±3.0 m/s | Strong, variable |

---

## File Map

```
scripts/terrain/
    terrain_data.gd              # TerrainData — heightmap + zones + query API
    heightmap_generator.gd       # Static pipeline: noise → zones → carving → TerrainData
    terrain_mesh_builder.gd      # Static: TerrainData → ArrayMesh + ConcavePolygonShape3D

scripts/
    hole_generator.gd            # HoleLayout generation (routing, obstacles, hazards, wind)
    hole_gen_config.gd           # Difficulty config resource
    procedural_hole.gd           # Scene builder: HoleLayout → Node3D tree

scripts/hazards/
    dynamic_hazard_base.gd       # Base class: IDLE→WARNING→ACTIVE state machine
    rock_slide_hazard.gd         # Canyon: rolling boulders with proximity collision
    sand_geyser_hazard.gd        # Desert: erupting sand column with area collision

scripts/managers/
    course_manager.gd            # Biome sequencing, hole progression, RNG ownership

resources/
    biome_definition.gd          # BiomeDefinition resource (all biome params)
    zone_definition.gd           # ZoneDefinition resource (per-zone physics/visuals)
    biome_segment.gd             # BiomeSegment resource (biome + hole count for sequencing)
    biomes/
        meadow.tres              # Gentle terrain, light wind, water at 0.0
        canyon.tres              # Dramatic elevation, moderate wind, rock slides
        desert.tres              # Sandy dunes, strong wind, sand geysers
```
