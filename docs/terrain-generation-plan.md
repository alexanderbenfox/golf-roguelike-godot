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

## Deterministic Generation & Seed System

The entire terrain generation pipeline must produce **bit-identical results** given the same seed and parameters — across network clients, across sessions, and (with caveats) across platforms. This is essential for multiplayer correctness, seed sharing, and debugging.

### Current State

The foundation is in place:

1. **Single shared RNG** — `CourseManager.generate_course(seed)` creates one `RandomNumberGenerator`, seeds it with `game_state.course_seed`, and threads it through every hole in sequence
2. **Sequential consumption** — holes are generated in order (1, 2, 3...), each consuming RNG state deterministically. The Nth hole always gets the same RNG state for a given seed
3. **Derived noise seeds** — `HeightmapGenerator` pulls `rng.randi()` to seed `FastNoiseLite`, so terrain noise is deterministic from the course RNG
4. **No global RNG contamination** — gameplay randomness (accuracy spread, upgrade rolls) uses separate `randf()` calls, not the course RNG
5. **Network seed sync** — `GameState.course_seed` is serialized via `to_dict()`/`from_dict()` for transmission to clients

### Determinism Rules

Any code that participates in terrain or course generation **must** follow these rules:

| Rule | Why |
|------|-----|
| **Never use global `randf()`/`randi()` in generation code** | Global RNG state varies per client based on unrelated events (UI, particles, etc.) |
| **Always consume from the shared `rng: RandomNumberGenerator`** | Ensures identical draw sequence across clients |
| **Fixed iteration order over all collections** | `Dictionary` iteration order is insertion-order in Godot 4, but be explicit — use `Array` where order matters |
| **No generation logic in `_process` / `_physics_process`** | Frame timing varies; generation must be a single synchronous pass |
| **No floating-point-sensitive branching** | Avoid `if height > threshold` where tiny float differences could flip the branch — use snapped/quantized comparisons when branching on generated values |
| **Document RNG draw count per function** | If a function draws N values from the RNG, that count must not change without updating all callers — an extra draw shifts every subsequent hole |

### RNG Draw Order Contract

The course RNG is consumed in a strict sequence. Adding or removing a draw anywhere shifts all downstream state. The current draw order per hole in `HoleGenerator.generate()`:

```
Per hole (in order):
  1. hole direction        — rng.randf_range()
  2. hole length           — rng.randf_range()
  3. fairway width         — rng.randf_range()
  4. noise seed            — rng.randi()          [passed to HeightmapGenerator]
  5. wind direction        — rng.randf()
  6. wind strength         — rng.randf_range()
  7..N. obstacle placement — variable count of rng draws (trees, bunkers)
```

**The variable obstacle draw count (7..N) is a fragility point.** If obstacle density config differs between clients, all subsequent holes diverge. Mitigation strategies:

- **Option A: Fixed draw budget** — always consume a fixed number of RNG draws for obstacles, discarding unused values. Wasteful but robust.
- **Option B: Sub-RNG for obstacles** — derive a child seed (`rng.randi()`) and create a local `RandomNumberGenerator` for obstacle placement. The parent RNG always advances by exactly 1 draw regardless of obstacle count.
- **Recommended: Option B** — already used for noise seed derivation, consistent pattern.

### Seed Sharing & Display

Players should be able to share seeds for courses they enjoyed and replay them later.

#### Seed Format

The raw seed is a 64-bit integer — not human-friendly. Provide a display format:

```gdscript
# Encode seed as a compact alphanumeric string
static func seed_to_code(seed_value: int) -> String:
    # Base-36 encoding (0-9, A-Z), truncated to 8 chars
    var code := ""
    var val := absi(seed_value)
    var chars := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for i in 8:
        code = chars[val % 36] + code
        val /= 36
    return code

static func code_to_seed(code: String) -> int:
    # Reverse of seed_to_code
    var val := 0
    var chars := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for c in code.to_upper():
        val = val * 36 + chars.find(c)
    return val
```

Gives codes like `K7F2M9XP` — easy to read out, type in, or screenshot.

#### UI Touchpoints

| Where | What |
|-------|------|
| **Debug overlay (F3)** | Show raw seed + code. Already has `set_value()` infrastructure — just add `debug_overlay.set_value("seed", seed_to_code(course_seed))` |
| **Hole complete screen** | Small seed code in the corner (non-intrusive) |
| **Course complete screen** | Prominent seed code + "Copy to Clipboard" button |
| **Main menu / lobby** | "Enter Seed" text field for manual seed entry. Empty = random seed |
| **Pause menu** | Display current seed code |

#### Seed Saving

Players can save seeds for later replay:

```gdscript
# In a SeedLibrary autoload or save file:
var saved_seeds: Array[Dictionary] = []
# Each entry:
# {
#     "code": "K7F2M9XP",
#     "seed": 1234567890,
#     "biome_sequence": "Meadow×3, Canyon×3, Desert×3",
#     "date_saved": "2026-03-19",
#     "note": ""  # optional player note
# }
```

Persisted to `user://saved_seeds.cfg` alongside `meta_progression.cfg`.

### Parameter Versioning

A seed alone isn't enough for reproducibility — the same seed with different biome parameters or generation code produces different terrain. For seed sharing to be meaningful across game versions:

| Approach | Tradeoff |
|----------|----------|
| **Version tag on seeds** | Store a generation version number alongside each seed. If the version doesn't match current, warn the player that results may differ. Simple, honest. |
| **Frozen parameter snapshots** | Save the full `BiomeSegment` + `HoleGenConfig` alongside the seed. Guarantees identical replay but bulkier save data. |
| **Recommended: Version tag** | Simpler. Most players share seeds within the same patch. Add `generation_version: int` to `GameState` and increment it whenever the generation pipeline changes in a way that would alter output. |

```gdscript
# In GameState:
const GENERATION_VERSION: int = 1  # bump when pipeline output changes

# In saved seed entry:
# { "code": "K7F2M9XP", "seed": 1234567890, "gen_version": 1, ... }
```

When loading a seed with a mismatched version: show a notice ("This seed was created in an earlier version — terrain may differ") but allow it anyway.

### Cross-Platform Determinism

Godot's `RandomNumberGenerator` uses PCG (permuted congruential generator) — deterministic and portable across platforms. `FastNoiseLite` is also deterministic given the same seed and parameters. The main risk is **floating-point arithmetic differences**:

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Different CPU float rounding** (x86 vs ARM) | Low — Godot uses 64-bit doubles in GDScript | Monitor; unlikely to cause visible divergence in terrain |
| **Different Godot versions** | Medium — engine math can change between versions | Pin Godot version for multiplayer compatibility |
| **Debug vs release builds** | Low — GDScript math is identical | No action needed |
| **GDExtension noise implementations** | Medium — if switching to a native noise lib | Always use Godot's built-in `FastNoiseLite` for terrain |

For multiplayer, all clients run the same Godot version and exported build, so cross-platform float risk is effectively zero in practice. For seed sharing across patches, the version tag handles it.

### Verification

To catch determinism regressions:

**Debug tool — Terrain Checksum:**
```gdscript
# In TerrainData:
func compute_checksum() -> int:
    var hash := 0
    for h in heights:
        hash = hash * 31 + int(h * 1000.0)  # quantize to avoid float noise
    for z in zones:
        hash = hash * 31 + z
    return hash
```

- Log checksum per hole during generation
- In multiplayer, each client can emit its checksum; server compares and flags mismatches
- In development, a unit test generates the same seed twice and asserts identical checksums

**Automated regression test:**
```gdscript
func test_determinism():
    var seed := 42
    var checksums_a := _generate_course_checksums(seed)
    var checksums_b := _generate_course_checksums(seed)
    assert(checksums_a == checksums_b, "Determinism broken: same seed produced different terrain")
```

### Resolved Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **RNG strategy** | Single shared `RandomNumberGenerator` per course | Simpler than per-hole seeding; deterministic draw order is sufficient |
| **Obstacle RNG fragility** | Sub-RNG derivation (Option B) | Fixed draw count from parent RNG regardless of obstacle density |
| **Seed display format** | Base-36 alphanumeric code (8 chars) | Human-readable, typeable, screenshot-friendly |
| **Cross-version seeds** | Version tag with warning | Simple; doesn't block replay, just informs |
| **Verification** | Quantized checksum per hole | Cheap, catches regressions, usable in multiplayer |

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
| **6** | Terrain textures (splatmap shader) + slope-dependent texturing + run-based biome progression | **Partial** — .tres biomes done, slope coloring & shader & run manager deferred |
| **7** | Wind mechanics + wind UI | **Complete** |
| **8** | Dynamic/timed hazards (geysers, boulders, lightning) | Planned |
| **9** | Hazard mitigation upgrades (Stone Skipper, Heat Rising) | Planned |
| **10** | Advanced routing + terrain archetypes (doglegs, island archipelago, valley corridors) | Planned |
| **11** | Terrain modifiers — roguelike integration (TerrainModifierStack, override cards) | Planned |
| **12** | Seed system — display UI, sharing codes, seed entry, saving, sub-RNG refactor, checksums | **Partial** — RNG threading done, UI & verification not started |

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
| **Slope texturing** | Vertex color blend by steepness (Phase A), shader-based (Phase B) | Immediate visual win with no shader work; steep faces look like cliffs not grass |
| **Terrain archetypes** | Enum on BiomeDefinition (Continental/Island/Valley Corridor) | Archetypes change terrain shape; biomes change look/mechanics — orthogonal axes of variation |
| **Seed format** | Base-36 alphanumeric code (8 chars) | Human-readable, typeable, screenshot-friendly for sharing |
| **Determinism verification** | Quantized checksum per hole | Cheap to compute, catches regressions, usable in multiplayer mismatch detection |
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

### Phase 10: Advanced Routing & Terrain Archetypes

Phase 10 expands from simple dogleg routing to full terrain archetypes — fundamentally different course shapes that change how terrain is generated, not just how the fairway is routed. Inspired by Super Battle Golf's island chains and winding valley courses.

#### 10a: Routing Enhancements
- Dogleg waypoints (1–2 turn points for par 4–5)
- Multi-spine fairway routing (alternate paths)

#### 10b: Terrain Archetype — Island Archipelago

A chain of raised landmasses separated by water, connected by narrow fairway bridges.

**Visual reference:** Super Battle Golf's tropical/island courses — distinct island platforms with fairways winding between them over open water, palm trees on island edges, greens on their own small islands.

**Generation approach:**
1. **Base elevation below water** — default terrain height starts below `water_height`, so everything is submerged unless explicitly raised
2. **Island mask generation** — place N island blobs (2–5 depending on par) along the fairway spine using radial falloff shapes (circles, ellipses, organic noise-perturbed blobs)
3. **Island elevation** — raise each island above water height with per-island noise for natural variation (plateaus, gentle mounds)
4. **Fairway bridges** — connect islands with narrow raised strips following the fairway spine, width tapers to ~60–80% of normal fairway width on bridges
5. **Green island** — the final island hosts the green; optionally a standalone small island for "island green" challenge holes
6. **Tee island** — first island hosts the tee, always the largest/most generous

**New BiomeDefinition parameters:**
```gdscript
@export var terrain_archetype: TerrainArchetype = TerrainArchetype.CONTINENTAL  # enum: CONTINENTAL, ISLAND, VALLEY_CORRIDOR
@export_range(2, 6) var island_count: int = 3          # number of islands (auto-scaled by par)
@export_range(10.0, 40.0) var island_radius_min: float = 15.0
@export_range(20.0, 60.0) var island_radius_max: float = 35.0
@export_range(0.0, 1.0) var island_noise_distortion: float = 0.3  # organic edge variation
@export_range(0.5, 1.0) var bridge_width_factor: float = 0.7      # bridge width as fraction of fairway width
```

**Island placement algorithm:**
- Walk along the fairway spine, placing islands at roughly even intervals
- Each island center is offset slightly from the spine for visual interest
- Island radii are randomized within min/max range
- Overlap between adjacent islands is allowed (creates natural merged landmasses)
- Rough zones extend to island edges; beyond the island mask → water

#### 10c: Terrain Archetype — Winding Valley Corridor

Fairway snakes through a narrow corridor carved between large hills, mesas, or mountain ridges. The playable area is a valley floor with imposing terrain walls on both sides.

**Visual reference:** Super Battle Golf's desert/Egyptian courses — fairway winds around deep sand pits with large elevated terrain on the sides, and canyon-like corridors between rock formations.

**Generation approach:**
1. **High base elevation** — default terrain starts tall (hills/ridges everywhere)
2. **Corridor carving** — carve a winding valley along the fairway spine, lowering terrain within a corridor width
3. **Spine curvature** — use a spline with 3–5 control points (more than standard doglegs) to create S-curves and switchbacks
4. **Valley floor** — the carved corridor floor gets gentle terrain noise for natural variation (not flat)
5. **Valley walls** — steep transitions from valley floor to surrounding high terrain, with configurable wall steepness
6. **Side valleys/alcoves** — optional branching pockets off the main corridor for bunker placements or risk/reward shortcuts
7. **Overlook points** — some hills can have flattened tops for elevated tee boxes that look down into the valley

**New BiomeDefinition parameters:**
```gdscript
@export_range(1.0, 3.0) var corridor_width_multiplier: float = 1.5  # corridor width as multiple of fairway_width
@export_range(0.0, 1.0) var wall_steepness: float = 0.7             # 0 = gentle slopes, 1 = near-vertical cliffs
@export_range(3, 7) var spine_control_points: int = 4                # spline complexity for winding paths
@export_range(0.0, 1.0) var alcove_density: float = 0.3             # chance of side pockets along corridor
@export_range(5.0, 20.0) var ridge_height: float = 12.0             # height of surrounding ridges above valley floor
```

**Corridor carving algorithm:**
- Generate a winding spline through the terrain with randomized control points
- For each terrain cell, compute distance to the nearest point on the spline
- Within corridor width: lower terrain to valley floor height + gentle noise
- Transition zone (corridor edge to ridge): steep blend controlled by `wall_steepness`
- Beyond transition: terrain stays at ridge height + noise

#### 10d: Archetype Combinations

Archetypes can combine with any biome for distinct feels:
| Archetype | + Meadow | + Canyon | + Desert | + Volcanic |
|-----------|----------|----------|----------|------------|
| **Continental** | Classic rolling hills | Ridge walks | Dune fields | Craggy plateaus |
| **Island** | Tropical islands (palm trees, blue water) | Rocky sea stacks | Oasis islands in sand sea | Lava-surrounded rock islands |
| **Valley Corridor** | Rolling meadow valleys | Deep slot canyons | Winding wadis between dunes | Lava river corridors |

### Splatmap Shader (Phase 6 remainder)
Zone map texture → shader with per-zone albedo/normal/roughness. Infrastructure ready (UVs, material_override slot, ZoneDefinition.texture). Needs texture assets.

### Slope-Dependent Texturing (Phase 6 extension)

Steep terrain faces should render with a different color/texture than flat or gently sloped surfaces. Inspired by Super Battle Golf, where hill/cliff faces are visibly distinct from plateau tops — e.g., a grassy plateau with brown/rocky cliff sides, or sandy dunes with darker exposed faces on steep slopes.

**Why this matters:** Without slope coloring, a tall hill looks like a uniform green blob. With it, the vertical faces read as cliffs/walls, adding depth and making elevation changes much more legible to the player.

**Implementation — Phase A: Vertex Color (immediate, no shader needed):**

During mesh building in `TerrainMeshBuilder`, compute the slope angle at each vertex and blend the vertex color toward a slope color when steepness exceeds a threshold:

```gdscript
# Per-vertex during mesh construction:
var normal := terrain_data.get_normal_at(wx, wz)
var steepness := 1.0 - normal.y  # 0 = flat, 1 = vertical wall
var slope_factor := clampf((steepness - slope_threshold) / (1.0 - slope_threshold), 0.0, 1.0)
var final_color := zone_color.lerp(slope_color, slope_factor)
```

**New BiomeDefinition parameters:**
```gdscript
@export var slope_color: Color = Color(0.45, 0.35, 0.25)  # cliff/slope face color (brownish rock default)
@export_range(0.0, 1.0) var slope_threshold: float = 0.4  # steepness below which no blending occurs (normal.y < 0.6)
@export_range(0.0, 1.0) var slope_color_strength: float = 0.8  # max blend toward slope_color at vertical
```

Each biome gets appropriate slope colors:
| Biome | Slope Color | Feel |
|-------|-------------|------|
| **Meadow** | Warm brown `(0.45, 0.35, 0.25)` | Exposed earth/dirt on hillsides |
| **Canyon** | Red-brown rock `(0.55, 0.30, 0.20)` | Sandstone cliff faces |
| **Desert** | Dark tan `(0.50, 0.40, 0.28)` | Compacted sand/hardpan on dune faces |
| **Volcanic** | Dark grey `(0.25, 0.22, 0.20)` | Basalt/obsidian cliff faces |

**Implementation — Phase B: Shader-based (with splatmap):**

When the splatmap shader is implemented, slope blending moves into the shader for per-pixel precision:
- Pass `slope_color` and `slope_threshold` as shader uniforms
- Compute steepness from the fragment normal (or a baked slope map texture)
- Blend per-zone albedo toward `slope_color` based on steepness
- Optionally sample a separate cliff texture (rock, dirt) instead of a flat color for more visual detail

### Phase 11: Terrain Modifiers — Roguelike Integration {#terrain-modifiers-roguelike-integration}

Roguelike modifiers that let the player alter terrain generation parameters for upcoming holes. Picked through the same between-hole upgrade screen as stat upgrades.

**Full modifier system design (including non-terrain modifiers like ball actions) is in [roguelike-modifiers-plan.md](roguelike-modifiers-plan.md).**

#### TerrainModifierStack

A per-player data structure that accumulates terrain overrides during a run. The `HeightmapGenerator` reads from this stack when generating each hole.

```gdscript
class TerrainModifierStack:
    var overrides: Array[TerrainOverride] = []

    func get_effective_value(param: StringName, base_value: float) -> float:
        var value := base_value
        for override in overrides:
            if override.param == param and override.holes_remaining != 0:
                value = override.apply(value)
        return value

    func tick_hole() -> void:
        # Decrement durations, remove expired overrides
        for override in overrides:
            if override.holes_remaining > 0:
                override.holes_remaining -= 1
        overrides = overrides.filter(func(o): return o.holes_remaining != 0)
```

```gdscript
class TerrainOverride:
    var param: StringName          # e.g., &"terrain_amplitude", &"fairway_width", &"water_height"
    var operation: int             # MULTIPLY or ADD (reuses UpgradeEffect.Operation)
    var value: float
    var holes_remaining: int       # -1 = rest of run, >0 = countdown
```

#### Integration Point

In `HeightmapGenerator`, before using any biome parameter, query the modifier stack:

```gdscript
var amplitude = modifier_stack.get_effective_value(
    &"terrain_amplitude", biome.terrain_amplitude
)
```

This is transparent to the rest of the pipeline — no changes needed downstream.

#### Example Terrain Modifiers

| Modifier | Param | Operation | Value | Duration | Player Fantasy |
|----------|-------|-----------|-------|----------|----------------|
| Landscaper | `terrain_amplitude` | MULTIPLY | 0.7 | 3 holes | "I flattened the course" |
| Channel Digger | `fairway_width` | MULTIPLY | 1.25 | 3 holes | "Wide open fairways" |
| Drought | `water_height` | ADD | -1.0 | Rest of run | "The water receded" |
| Flood Warning | `water_height` | ADD | +1.0 | 1 hole | "Rising tides" (risk/reward pick) |
| Wind Shield | `base_wind_strength` | MULTIPLY | 0.5 | 3 holes | "Calm conditions" |
| Mountain Maker | `terrain_amplitude` | MULTIPLY | 1.5 | 1 hole | "Extreme terrain" (risk/reward) |
| Archipelago Map | `terrain_archetype` | SET | ISLAND | 1 hole | "Force an island layout" |
| Valley Map | `terrain_archetype` | SET | VALLEY_CORRIDOR | 1 hole | "Force a valley layout" |

#### As Upgrade Cards

Terrain modifiers use a new `UpgradeEffect.stat` value (`TERRAIN_OVERRIDE`) so they flow through the existing `UpgradeDefinition` / `UpgradeRegistry` / upgrade screen without special-casing:

```gdscript
# In UpgradeEffect:
enum Stat { POWER, FRICTION, BOUNCE, ACCURACY, GRAVITY, TERRAIN_OVERRIDE, ACTION }
```

The `apply(player)` method on terrain override effects writes into `player.terrain_modifier_stack` instead of modifying stats directly.

### Run-Based Progression (Phase 6 remainder)
Run manager builds `biome_sequence` dynamically based on meta progression level. Each run introduces one new biome.
