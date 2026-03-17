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

Each biome is a `.tres` resource with exported parameters:

- **Colors**: fairway, rough, green, tee, hazard, water, OOB
- **Terrain noise**: amplitude, frequency, octaves, lacunarity, persistence, ridge mode
- **Elevation constraints**: max height, fairway flatten strength, green/tee flatten radius
- **Hazard planes**: water_height, lava_height
- **Obstacles**: available types + density multiplier
- **Mechanics**: base wind, wind variance, weather flag, friction modifiers per zone
- **Progression**: difficulty tier, min meta level to unlock

### Biome Progression

**Linear escalation**: Run 1 = Meadow, Run 2 = Canyon, Run 3 = Desert, etc. Each run introduces exactly one new biome. **Per-course biome** (all 9 holes share one biome for visual cohesion). Terrain parameters escalate within the course (hole 1 = gentle, hole 9 = aggressive).

---

## Terrain Generation Pipeline

Called from `HoleGenerator.generate()`, five steps:

### Step 1: Hole Routing
- Place tee at origin, determine direction/length (existing logic)
- Pick tee and cup elevations from biome range
- For par 4-5: optionally generate **dogleg waypoints** (1-2 turn points)
- Build a **fairway spine** -- array of Vector3 control points from tee to cup
- This spine is the "intended path" the fairway carves through terrain

### Step 2: Heightmap Generation
- Configure `FastNoiseLite` from biome noise params + seeded RNG
- Allocate height grid (cell_size ~2m, so a 300x100m hole = ~7,500 cells, ~30KB)
- Sample noise for each cell to get raw height
- **Carve the fairway**: for each cell, compute distance to nearest spine segment. Within fairway width, blend height toward the spine's intended elevation using `fairway_flatten_strength`. This creates a smooth corridor through hilly terrain.
- **Flatten the green**: within radius of cup, force height toward cup_elevation with smooth falloff
- **Flatten the tee**: same for tee position
- Clamp to biome's elevation range

### Step 3: Zone Painting
Assign each cell a zone type based on proximity + height:

| Zone | Rule |
|------|------|
| TEE | Within tee_flatten_radius of tee |
| GREEN | Within green_flatten_radius of cup |
| FAIRWAY | Within fairway_width of spine AND height near intended |
| BUNKER | Within placed bunker radius |
| WATER | Height < water_height |
| LAVA | Height < lava_height |
| ROUGH | All other playable terrain |
| OOB | Beyond hole boundary margin |

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
| **4** | Zone system + friction | Rough/fairway/bunker/green affect ball differently |
| **5** | Water/lava hazards + hazard plane rendering | Hybrid penalty system (water=teleport, lava=bounce) |
| **6** | BiomeDefinition resources + linear progression | Multiple biomes with distinct identity |
| **7** | Wind + weather mechanics | Per-biome atmospheric effects |
| **8** | Dynamic/timed hazards | Geysers, boulders, lightning per biome |
| **9** | Hazard mitigation upgrades | Stone Skipper, Heat Rising, etc. in upgrade pool |
| **10** | Advanced routing (doglegs, island greens) | Strategic hole layouts |

Each phase is independently testable and the game stays playable throughout.

Phase 1 is complete -- `TerrainData` and `HeightmapGenerator` are implemented and wired through `HoleGenerator -> ProceduralHole -> GolfBall -> PhysicsSimulator`. Currently outputs flat terrain so the game plays identically to before.

Phase 2 is complete -- `TerrainMeshBuilder` generates vertex-coloured ArrayMesh + ConcavePolygonShape3D from heightmap data. `HeightmapGenerator` now uses FastNoiseLite for rolling hills with fairway carving and green/tee flattening. `ProceduralHole` replaced flat BoxShape3D + PlaneMesh overlays with terrain mesh + collision. `PhysicsSimulator` queries terrain height for ground detection. `TrajectoryDrawer` uses terrain height for ribbon clamping, landing detection, and halo placement. Obstacles placed at terrain surface height.

---

## New File Structure

```
scripts/terrain/
    terrain_data.gd              # TerrainData (heightmap + zones + queries)
    heightmap_generator.gd       # Static: noise -> routing-carved heightmap
    terrain_mesh_builder.gd      # Static: TerrainData -> ArrayMesh + collision
    biome_decorator.gd           # Cosmetic props (grass tufts, particles)
    obstacle_builder.gd          # Per-type obstacle mesh creation

resources/
    biome_definition.gd          # BiomeDefinition resource class
    biomes/
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
