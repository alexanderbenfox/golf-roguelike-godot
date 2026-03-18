# Procedural Terrain Generation System — Design Plan

## Context

The current terrain system is entirely flat: a single `BoxShape3D` ground plane at y=0.5 with `PlaneMesh` overlays for fairway/green/tee. There are no hills, no water, no elevation changes. This plan redesigns terrain generation to support rolling hills, water hazards, mountainous walls, biome-specific obstacles, and proper golf course structure (fairway, rough, green, bunkers) — all procedurally generated from a seed.

Inspired by Mario Golf: Super Rush's biome progression (Meadow -> Canyon -> Desert -> Storm Forest -> Volcanic), where each biome introduces new mechanics, not just visuals.

---

## Architecture Overview

Three new layers, following the existing pattern of "pure data first, scene building second":

```
BiomeDefinition (Resource)     <-- describes rules, colors, noise params, mechanics per biome
        |
HeightmapGenerator (static)    <-- produces TerrainData from noise + hole routing
        |
TerrainMeshBuilder (static)    <-- converts TerrainData into ArrayMesh + collision shape
```

The central data structure is **TerrainData** -- a grid-based heightmap + zone map that everything queries: physics, trajectory preview, mesh building, obstacle placement.

---

## Biome System

### Biome Types (6, matching Mario Golf's escalating difficulty)

| Biome | Theme | Key Features | New Mechanic |
|-------|-------|-------------|--------------|
| **Meadow** | Classic golf, gentle hills | Wide fairways, mild slopes, light bunkers | Baseline -- no special mechanics |
| **Canyon** | Ridges, mesas, cliffs | Dramatic elevation, narrow bridges, water below | Multi-tiered fairways, island greens |
| **Desert** | Dunes, sand, arid | Sand waste areas, cacti, wide bunkers | Strong variable wind, heavy sand friction |
| **Storm Forest** | Dense trees, rain | Narrow corridors, tall canopy, mud patches | Rain reduces roll, wind gusts shift mid-hole |
| **Volcanic** | Lava, dark rock, crags | Lava pits (= water penalty), sharp elevation, rock walls | Lava hazards, hard rocky bounces |
| **Urban** | Rooftops, concrete | Flat elevated platforms, gap jumps, walls | Hard surfaces (extreme bounce/roll) |

### BiomeDefinition Resource (`resources/biome_definition.gd`)

Each biome is a Resource with exported parameters. **Implemented (Phase 4):**

- **Zone definitions**: `Array[ZoneDefinition]` — each zone has `color`, `friction`, `bounce_modifier`, `texture`
- **Material override**: optional `Material` slot (for splatmap shader or simple textured terrain)
- **UV scale**: controls world-space UV tiling density
- **Default factory**: `BiomeDefinition.create_meadow()` provides the baseline biome

**Planned additions (Phase 6+):**

- **Terrain noise**: amplitude, frequency, octaves, lacunarity, persistence, ridge mode
- **Elevation constraints**: max height, fairway flatten strength, green/tee flatten radius
- **Hazard planes**: water_height, lava_height
- **Obstacles**: available types + density multiplier
- **Mechanics**: base wind, wind variance, weather flag
- **Progression**: difficulty tier, min meta level to unlock
- **Splatmap shader**: terrain ShaderMaterial + per-zone textures via ZoneDefinition.texture

### Biome Progression & Course Sequencing

Biome progression is configured via `CourseManager.biome_sequence` — an `Array[BiomeSegment]` editable in the Inspector. Each `BiomeSegment` pairs a `BiomeDefinition` with a `hole_count`:

```
biome_sequence:
  [0]: BiomeSegment { biome: Meadow,  hole_count: 3, cell_size: 2.0, margin: 30.0 }
  [1]: BiomeSegment { biome: Canyon,  hole_count: 3, cell_size: 1.5, margin: 40.0 }
  [2]: BiomeSegment { biome: Desert,  hole_count: 3, cell_size: 2.0, margin: 50.0 }
  → 9-hole course: holes 1-3 = Meadow, 4-6 = Canyon (higher res), 7-9 = Desert (wider bounds)
```

**Sequence rules:**
- Holes generate in order of the array, each using its segment's biome
- Total holes = sum of all `hole_count` values (no separate `holes_in_course` needed)
- When `biome_sequence` is empty, falls back to `holes_in_course` × default Meadow biome
- Each segment's biome controls zone colors, friction, material, noise params, and terrain shaping
- Each segment also controls `cell_size` (terrain resolution) and `margin` (terrain bounds beyond playable area)
- `HoleGenConfig` still controls difficulty parameters (par ranges, fairway width, obstacle density) shared across all segments

**Run-based escalation (future):** A run manager could build the `biome_sequence` dynamically: Run 1 = [Meadow×9], Run 2 = [Meadow×5, Canyon×4], Run 3 = [Meadow×3, Canyon×3, Desert×3], etc. Each run introduces one new biome while keeping earlier biomes in the mix.

---

## Terrain Generation Pipeline

Called from `HoleGenerator.generate()`, six steps. Note: zone painting is done **first** (it only uses XZ spatial rules, no height dependency), which enables per-zone height modifiers in step 3.

### Step 1: Zone Painting
Assign each cell a zone type based on proximity (XZ only):

| Zone | Rule |
|------|------|
| TEE | Within tee_flatten_radius of tee |
| GREEN | Within green_flatten_radius of cup |
| FAIRWAY | Within fairway_width of spine |
| BUNKER | Within placed bunker radius |
| WATER | Height < water_height (post-height pass) |
| LAVA | Height < lava_height (post-height pass) |
| ROUGH | All other playable terrain |
| OOB | Beyond hole boundary margin |

### Step 2: Heightmap Generation
- Configure `FastNoiseLite` from biome noise params (`terrain_frequency`, `terrain_amplitude`, `noise_octaves`, `noise_lacunarity`, `noise_gain`) + seeded RNG
- Allocate height grid (`cell_size` from BiomeSegment, default ~2m)
- Sample noise for each cell to get raw height centred on `ground_height`

### Step 3: Per-Zone Height Modifiers
For each cell, look up the zone's `ZoneDefinition` and reshape the terrain:
- Split noise delta into hill (positive) or valley (negative) relative to `ground_height`
- Apply **shape exponent** (`hill_shape` / `valley_shape`): < 1.0 = rounded/plateau, 1.0 = linear, > 1.0 = peaked/V-shaped
- Apply **scale** (`hill_scale` / `valley_scale`): 0.0 = flat, 1.0 = full noise, 2.0 = exaggerated
- Add **height_offset** (e.g., bunkers = -0.3 for slight depression)

```gdscript
if delta > 0:
    delta = pow(delta, zone_def.hill_shape) * zone_def.hill_scale
else:
    delta = -pow(abs(delta), zone_def.valley_shape) * zone_def.valley_scale
height = ground_height + delta + zone_def.height_offset
```

### Step 4: Fairway Carving
- For each cell near the fairway spine, blend height toward the spine's intended elevation using `biome.fairway_flatten_strength`
- Quadratic falloff: centre = full flattening, edges blend into rough
- This overrides per-zone height modifiers within the fairway, keeping it smooth

### Step 5: Green/Tee Flattening
- Flatten terrain in a circular area around cup (`biome.green_flatten_radius`) and tee (`biome.tee_flatten_radius`)
- Quadratic falloff: centre snaps to `ground_height`, edge blends

### Step 6: Height Clamping
- Clamp all cells to `biome.min_height` / `biome.max_height`

### Step 7: Hole Routing (unchanged)
- Place tee at origin, determine direction/length (existing logic)
- For par 4-5: optionally generate **dogleg waypoints** (1-2 turn points, future)
- Build a **fairway spine** -- array of Vector3 control points from tee to cup

### Step 4: Obstacle Placement (Static + Dynamic)
- Use biome's obstacle type list and density
- Only spawn in ROUGH zones (never fairway/green/water)
- Query `terrain_data.get_height_at()` for correct Y placement
- Existing tree/bunker logic preserved, extended with new types (rocks, cacti, palm trees, lava rocks)

**Dynamic/timed hazards** escalate with biome difficulty:
- **Meadow**: No dynamic hazards (pure golf)
- **Canyon**: Periodic rock slides (timed, predictable pattern)
- **Desert**: Sand geysers that erupt on a timer, launching nearby balls
- **Storm Forest**: Lightning strikes at semi-random intervals near the fairway
- **Volcanic**: Rolling boulders on patrol paths, geysers of lava
- **Urban**: Timed barriers/gates that open and close

Dynamic hazard **density is editor-configurable** on BiomeDefinition:
```gdscript
@export_range(0.0, 3.0) var dynamic_hazard_density: float = 1.0
@export_range(0.0, 3.0) var timed_hazard_density: float = 1.0
```

### Step 5: Wind Generation
- If biome has wind: roll direction + strength from seeded RNG
- Store on HoleLayout for physics and UI display

---

## TerrainData -- The Central Data Structure

```
TerrainData (RefCounted)
+-- heights: PackedFloat32Array    # grid-based heightmap
+-- zones: PackedByteArray         # zone type per cell
+-- grid_width, grid_depth, cell_size, origin
+-- noise: FastNoiseLite           # stored for potential re-sampling
+-- tee_position, cup_position: Vector3 (with correct Y)
+-- fairway_spine: Array[Vector3]
+-- water_height, lava_height: float
|
+-- get_height_at(x, z) -> float           # bilinear interpolation
+-- get_normal_at(x, z) -> Vector3         # from neighboring samples
+-- get_zone_at(x, z) -> ZoneType          # nearest cell lookup
+-- get_friction_at(x, z) -> float         # zone-based friction modifier
```

Pre-computed grid (not real-time noise sampling) because:
- Generation applies fairway carving + flattening that can't be expressed as pure noise
- Bilinear interpolation of a grid is faster than multi-octave noise per physics frame
- 30KB per hole is negligible memory

---

## Terrain Mesh Building

`TerrainMeshBuilder` converts TerrainData into renderable geometry:

1. **ArrayMesh via SurfaceTool** -- two triangles per grid cell, standard heightmap triangulation
2. **Vertex colors** per vertex from zone type (using biome's color palette), blended at zone boundaries
3. **Normals** auto-generated by SurfaceTool
4. **ConcavePolygonShape3D** from the same triangles for collision
5. **Water plane** -- semi-transparent PlaneMesh at water_height (visual only; physics handles water via height check)

Single MeshInstance3D + StaticBody3D per hole. Matches existing flat-color art style (no textures needed).

### Textured Terrain Rendering (Future)

The mesh currently renders with vertex colors, but is built to support textured rendering via two mechanisms on `BiomeDefinition`:

**Mechanism 1: Simple material override**
Set `material_override` on BiomeDefinition to any `StandardMaterial3D` with an albedo texture. The mesh already has world-space UVs (`world_xz * uv_scale`), so a tiling grass texture works immediately. Good for a quick visual upgrade but applies one texture to the entire terrain.

**Mechanism 2: Splatmap shader (per-zone textures)**
For distinct materials per zone (grass fairway, sand bunker, rock rough, etc.), use a splatmap approach:

1. **Zone map texture** — Bake `TerrainData.zones` (PackedByteArray) into an `ImageTexture` at generation time. Each pixel stores the zone type as a color channel or grayscale value. Add a helper to TerrainData:
   ```gdscript
   func bake_zone_map_texture() -> ImageTexture:
       var img := Image.create(grid_width, grid_depth, false, Image.FORMAT_R8)
       for gz in range(grid_depth):
           for gx in range(grid_width):
               var zone_byte: int = zones[idx(gx, gz)]
               img.set_pixel(gx, gz, Color(zone_byte / 255.0, 0, 0))
       var tex := ImageTexture.create_from_image(img)
       return tex
   ```

2. **Terrain splatmap shader** — A `ShaderMaterial` that:
   - Receives the zone map texture + per-zone albedo/normal/roughness textures as uniforms
   - Samples the zone map at the fragment's UV to determine the zone
   - Blends between adjacent zone textures at boundaries (using a smoothstep over zone map gradients)
   - Tiles each zone texture independently using `uv_scale`

   Shader uniforms would look like:
   ```gdscript
   shader_type spatial;
   uniform sampler2D zone_map : filter_nearest;
   uniform sampler2D fairway_tex : source_color;
   uniform sampler2D rough_tex : source_color;
   uniform sampler2D green_tex : source_color;
   uniform sampler2D bunker_tex : source_color;
   uniform sampler2D water_tex : source_color;
   uniform float tile_scale = 10.0;
   uniform float blend_sharpness = 8.0;
   ```

3. **Wiring** — `BiomeDefinition.material_override` is set to the splatmap ShaderMaterial. Each `ZoneDefinition.texture` feeds into the shader's per-zone texture uniforms. `TerrainMeshBuilder` or `ProceduralHole` calls `bake_zone_map_texture()` and assigns it to the shader at build time.

4. **Vertex colors preserved** — Even with a splatmap shader, vertex colors are still generated. The shader can optionally multiply by vertex color for tinting/variation, or ignore them entirely.

**When to implement:** Phase 6 (BiomeDefinition resources) is the natural time, when each biome needs a distinct visual identity beyond color swaps. The infrastructure (UVs, material_override slot, per-zone texture slots) is already in place.

---

## Physics Changes

### PhysicsSimulator -- terrain-aware ground detection

`PhysicsParams` gains:
- `terrain: TerrainData` (null = flat ground, backward compatible)
- `wind: Vector3`

Ground check becomes:
```gdscript
ground_height_at_ball = terrain.get_height_at(pos.x, pos.z)  # instead of flat value
ground_normal = terrain.get_normal_at(pos.x, pos.z)          # instead of Vector3.UP
```

### Slope physics
- Gravity projects onto slope surface -> ball rolls downhill naturally
- Bounce reflects off terrain normal (not just UP)
- Friction applied along slope surface

### Zone friction
- FAIRWAY: normal friction
- ROUGH: increased friction (biome.rough_friction_modifier)
- BUNKER: heavy friction (~3x)
- GREEN: reduced friction (~0.7x)

`TerrainData` already stores per-zone friction values and exposes `get_friction_at(x, z)`.
Currently `PhysicsSimulator.simulate_step()` uses a single `params.ground_friction` for the
entire simulation. Phase 4 must change the ground friction step to query the terrain each frame:

```gdscript
# In simulate_step(), replace the fixed combined_friction with a per-position lookup:
var zone_friction: float = params.ground_friction
if params.terrain:
    zone_friction = params.terrain.get_friction_at(new_state.position.x, new_state.position.z)
var combined_friction := params.ball_friction * zone_friction
```

This will resolve the current bug where the ball rolls at the same speed everywhere regardless
of zone — in particular, off-fairway/rough areas feel too slippery because no extra friction
is applied.

### Wind
- Applied to velocity each frame while ball is airborne
- `velocity += wind * drag_coefficient * delta`

### Hazard System (Hybrid + Upgrade-Mitigable)

**Water**: Stroke penalty + teleport to last shot position (traditional golf).
**Lava**: Ball bounces out with momentum (arcade feel), lands nearby on safe ground.

Both hazards are **mitigable via roguelike upgrades**:
- "Stone Skipper" upgrade -> ball skips across water like a stone (N bounces before sinking)
- "Heat Rising" upgrade -> ball floats over lava on convection (reduced gravity near lava surface)
- Future upgrades could reduce penalty strokes, increase skip count, etc.

This ties into the existing `UpgradeEffect` system -- new `Stat` enum entries (e.g., `WATER_SKIP`, `LAVA_RESIST`) that modify hazard behavior in `PhysicsSimulator`. The `SimulationState` gains:
```gdscript
var in_water: bool = false
var in_lava: bool = false
var water_skip_count: int = 0    # from upgrade, decremented per skip
var lava_float_strength: float = 0.0  # from upgrade
```

---

## Affected Existing Systems

| System | Change |
|--------|--------|
| **PhysicsSimulator** | Terrain-aware ground, slopes, zone friction, wind |
| **GolfBall** | Receives TerrainData in setup, water/lava handling, wind params |
| **TrajectoryDrawer** | Ribbon clamps to terrain height instead of 0.52, landing detection uses terrain |
| **ProceduralHole** | Uses TerrainMeshBuilder instead of flat ground box |
| **HoleGenerator** | Extended with full terrain pipeline (routing -> heightmap -> zones -> wind) |
| **HoleGenConfig** | New terrain/biome params (elevation_scale, terrain_resolution, allow_doglegs) |
| **CourseManager** | Biome selection per course |
| **Camera** | Already raycasts for ground avoidance -- works with terrain collision automatically |
| **Main** | Passes terrain to ball, biome info to environment |

---

## Implementation Phases

| Phase | What | Validates |
|-------|------|-----------|
| **1** | TerrainData + HeightmapGenerator (flat output) | Data plumbing, no visual change |
| **2** | TerrainMeshBuilder + collision | Terrain is visually hilly, ball collides with it |
| **3** | Terrain-aware PhysicsSimulator | Ball rolls on slopes, trajectory matches terrain |
| **4** | Zone system + friction + BiomeDefinition/ZoneDefinition resources | Rough/fairway/bunker/green affect ball differently; editor-configurable per biome |
| **5** | Water/lava hazards + hazard plane rendering | Hybrid penalty system (water=teleport, lava=bounce) |
| **6** | Terrain textures (splatmap shader), saved .tres per biome, run-based biome progression | Multiple biomes with distinct visual identity + automated progression |
| **7** | Wind + weather mechanics | Per-biome atmospheric effects |
| **8** | Dynamic/timed hazards | Geysers, boulders, lightning per biome |
| **9** | Hazard mitigation upgrades | Stone Skipper, Heat Rising, etc. in upgrade pool |
| **10** | Advanced routing (doglegs, island greens) | Strategic hole layouts |

Each phase is independently testable and the game stays playable throughout.

Phase 1 is complete -- `TerrainData` and `HeightmapGenerator` are implemented and wired through `HoleGenerator -> ProceduralHole -> GolfBall -> PhysicsSimulator`. Currently outputs flat terrain so the game plays identically to before.

Phase 2 is complete -- `TerrainMeshBuilder` generates vertex-coloured ArrayMesh + ConcavePolygonShape3D from heightmap data. `HeightmapGenerator` now uses FastNoiseLite for rolling hills with fairway carving and green/tee flattening. `ProceduralHole` replaced flat BoxShape3D + PlaneMesh overlays with terrain mesh + collision. `PhysicsSimulator` queries terrain height for ground detection. `TrajectoryDrawer` uses terrain height for ribbon clamping, landing detection, and halo placement. Obstacles placed at terrain surface height.

Phase 3 is complete -- `PhysicsSimulator` uses terrain normals for slope-based gravity projection (ball rolls downhill), bounce reflects off terrain normal, and ground detection queries `terrain.get_height_at()` per frame.

Phase 4 is complete -- Zone-based friction is now live. `PhysicsSimulator.simulate_step()` queries `terrain.get_friction_at()` each frame instead of using a single `params.ground_friction`, so fairway, rough, bunker, and green all feel mechanically distinct. This phase also introduced the full `BiomeDefinition`, `ZoneDefinition`, and `BiomeSegment` resource system (pulled forward from Phase 6):

**BiomeDefinition** (Resource):
- `Array[ZoneDefinition]` for per-zone properties
- Terrain noise params: `terrain_amplitude`, `terrain_frequency`, `noise_octaves`, `noise_lacunarity`, `noise_gain`
- Elevation limits: `min_height`, `max_height`
- Fairway shaping: `fairway_flatten_strength`, `green_flatten_radius`, `tee_flatten_radius`
- Rendering: `material_override: Material`, `uv_scale`
- Static `create_meadow()` factory provides the default biome

**ZoneDefinition** (Resource):
- `color`, `friction`, `bounce_modifier`, `texture` (rendering + physics)
- Terrain shaping: `hill_scale`, `valley_scale` (amplitude multipliers), `hill_shape`, `valley_shape` (exponent: < 1 = rounded, > 1 = peaked), `height_offset` (constant vertical shift)

**BiomeSegment** (Resource):
- `biome: BiomeDefinition`, `hole_count: int`
- Terrain size: `cell_size` (grid resolution), `margin` (terrain bounds beyond playable area)

**Pipeline changes:**
- `HeightmapGenerator` reads noise/elevation/shaping params from BiomeDefinition instead of hardcoded constants
- Pipeline reordered: zones painted first (spatial rules only) → noise fill → per-zone height modifiers → fairway carving → green/tee flattening → height clamping
- `CourseManager.biome_sequence: Array[BiomeSegment]` drives course generation — each segment specifies biome, hole count, and terrain size
- `TerrainMeshBuilder` reads zone colors from biome, generates world-space UVs on every vertex
- `HoleGenConfig.biome` serves as fallback when no biome_sequence is set

Phase 5 is complete -- Water and lava hazards are now functional:

**BiomeDefinition** gains `water_height` and `lava_height` exports (default -999.0 = disabled). Meadow uses `water_height = -0.5`, Canyon uses `water_height = -1.5`, Desert has both disabled.

**HeightmapGenerator** pipeline extended with Step 7 (`_paint_hazard_zones()`): after height clamping, cells below `water_height`/`lava_height` are reassigned to WATER/LAVA zones (only ROUGH and OOB cells — spatial zones like GREEN, TEE, FAIRWAY are preserved). Terrain's `water_height`/`lava_height` are set from the biome so runtime queries work.

**ProceduralHole** renders semi-transparent hazard planes — blue water plane at `water_height + 0.05`, emissive orange/red lava plane at `lava_height + 0.05`. Both cover the full terrain grid extents, double-sided, unshaded.

**GolfBall** hazard detection:
- Water: checked when ball comes to rest. Teleports ball back to `last_shot_position` and emits `hit_water` signal (same pattern as OOB).
- Lava: checked every frame while ball is on ground. Applies an upward + lateral bounce (toward last shot position) so ball pops off lava and lands on safe ground. Max 3 bounces before force-teleporting like water. Emits `hit_lava` on first contact only.

**ScoringManager** gains `add_penalty(count)` for hazard stroke penalties (distinct from `add_stroke()` which represents a swing).

**Main** connects `hit_water` and `hit_lava` signals → `add_penalty(1)` + coloured hazard message ("Water Hazard! +1 Stroke" / "Lava! +1 Stroke").

---

## New File Structure

```
scripts/terrain/
    terrain_data.gd              # TerrainData (heightmap + zones + queries)
    heightmap_generator.gd       # Static: noise -> routing-carved heightmap
    terrain_mesh_builder.gd      # Static: TerrainData -> ArrayMesh + collision
    biome_decorator.gd           # Cosmetic props (grass tufts, particles) [future]
    obstacle_builder.gd          # Per-type obstacle mesh creation [future]

resources/
    zone_definition.gd           # ZoneDefinition resource (color, friction, texture per zone)
    biome_definition.gd          # BiomeDefinition resource (zones array + material override)
    biome_segment.gd             # BiomeSegment resource (biome + hole_count for course sequencing)
    biomes/                      # Saved .tres biome instances [future]
        meadow.tres
        canyon.tres
        desert.tres
        storm_forest.tres
        volcanic.tres
        urban.tres
```

---

## Resolved Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Hazard behavior** | Hybrid: water = penalty+teleport, lava = bounce-out | Both upgradable (stone skip, heat float) |
| **Biome progression** | Linear escalation across runs | Run 1=Meadow, 2=Canyon, etc. Clear progression |
| **Dynamic hazards** | Yes: timed/periodic in early biomes, free-roaming in later | Density is editor-configurable per biome |
| **Terrain resolution** | 2m cells (~7.5K tris) | Good starting point, can refine later |
| **Terrain detail** | 2m cell_size, ~150x50 grid per hole | ~30KB heightmap, fast bilinear interpolation |
| **Zone properties** | Editor-configurable via ZoneDefinition resources on BiomeDefinition | Designers tweak friction/color/texture per zone per biome in Inspector |
| **Terrain rendering** | Vertex colors now, splatmap shader later. UVs always generated. | material_override slot on BiomeDefinition enables drop-in texture support |
