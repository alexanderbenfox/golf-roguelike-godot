# Blender Asset Plan

Everything you need to build in Blender and how to get it into the game.
The game is written in Godot 4. All 3D imports use **.glb** format.

---

## Current State — What's Placeholder

| Element | Current state | Notes |
|---|---|---|
| Golf ball | `SphereMesh` r=0.2, basic material | `scenes/golf_ball.tscn` |
| **Character** | **Nothing — not yet implemented** | **Major future feature** |
| Trees | Procedural cone + cylinder | `scripts/procedural_hole.gd:_build_tree()` |
| Flag | Box mesh + cylinder pole | `scripts/procedural_hole.gd:_build_cup_visual()` |
| Rock boulders | `SphereMesh` r=0.8, flat brown | `scripts/hazards/rock_slide_hazard.gd` |
| Water/lava | Flat `PlaneMesh`, tinted material | Needs animated shader |
| Terrain | Vertex-colored heightmap | Has UV coords; ready for textures via `material_override` |
| Scenery | Nothing | No decorative props yet |

**Priority order:** Ball → Flag & Cup → Trees → Boulders → **Character + Clubs** → Decorative props → Terrain textures

---

## Godot 4 Blender Workflow — Universal Rules

### Export settings (every asset)
- Format: **glb** (File → Export → glTF 2.0)
- Include: **Geometry > Apply Modifiers** ✓
- Include: **Transform > +Y Up** ✓ (Godot is Y-up, Blender is Z-up — let Godot handle the conversion)
- Include: **Animation > NLA Strips** ✓ (for animated assets)
- **Apply all transforms** (Ctrl+A → All Transforms) before export
- **Triangulate** faces or enable "Triangulate Mesh" in export settings

### Scale
- **1 Blender unit = 1 metre** in Godot
- Check game units in the table below for each asset

### Materials
- Use **Principled BSDF** shader in Blender — it imports cleanly as StandardMaterial3D in Godot
- Keep textures embedded in the .glb (export option: Include > Data > Textures) OR place them separately in `resources/textures/` and link them after import
- Name your materials clearly (`Golf_Ball_White`, `Tree_Bark`, etc.) — Godot creates overrideable material slots by name

### Collision
**You do not need to model collision shapes** — the game defines them in code:
- Ball: `SphereShape3D` r=0.2 (already in scene)
- Trees: `CylinderShape3D` (already in code)
- Boulders: proximity detection in code, no physics shape needed

Your .glb mesh is purely visual in all cases.

### Importing in Godot
1. Drag the .glb into `assets/models/` in the Godot FileSystem
2. Godot auto-imports it — click it and use the Import panel to tune settings
3. For animated assets: Import panel → Animation → set Loop Mode on clips

---

## Asset 1 — Golf Ball

### What to model
A regulation golf ball with dimples. Radius = **0.2 m** (in game units — real balls are ~0.021m but 0.2 is used for gameplay visibility).

### Blender approach
1. Start from a UV Sphere, ~2–3 subdivisions
2. Add dimples: duplicate the sphere, shrink it slightly, use it as a boolean cutter in a pattern — or use a displacement modifier with a procedural dimple texture
3. Alternatively use a normal map to fake dimples (faster, looks fine at game scale)
4. Keep poly count **under 500 triangles** — it's tiny on screen

### Material
- **Base Color**: white (0.9, 0.9, 0.9) with slight warm tint
- **Metallic**: 0.0
- **Roughness**: 0.45 (slightly shiny)
- Optional: add a subtle logo/stripe on UV map

### How to hook it in
Replace the `SphereMesh` in `scenes/golf_ball.tscn`:
1. Import the .glb
2. In Godot, open `scenes/golf_ball.tscn`
3. Select the `MeshInstance3D` node under `RigidBody3D`
4. In the Inspector, change Mesh from `SphereMesh` to your imported `MeshInstance3D`'s mesh resource
5. The `SphereShape3D` collision and physics material stay unchanged

### Animations
None needed — the ball rotation in flight is handled by code (you can add a `rotate_object_local` call in `golf_ball.gd` for visual spin, but it's not critical).

---

## Asset 2 — Character & Clubs

This is the most complex asset in the game. The character is a humanoid golfer who:
- Stands behind the ball facing the aim direction during free aim
- Pulls back a backswing as the player holds the shoot button (power fills up)
- Swings through and impacts the ball when the player releases
- Holds a follow-through pose while the ball is in flight
- Idles/watches when it's not their turn

The **club** is a separate mesh parented to the character's hands.

---

### 2a — Character Model

#### Body specs
| Property | Value |
|---|---|
| Height | ~1.8 m (standing) |
| Poly count | 2,000–6,000 tris (visible from mid-distance) |
| UV unwrap | Single atlas, 1K or 2K texture |
| Style | Match the low-poly/stylized tone of the game |

#### What to model
A generic golfer silhouette — polo shirt, trousers, cap, glove. No hyper-detailed face needed; the camera is usually well above the character. A slightly stylized, readable silhouette at distance is more important than close-up detail.

#### Rig requirements
Use Blender's standard **Armature** with these bone groups:

| Group | Bones | Notes |
|---|---|---|
| Spine | Root, Hips, Spine, Chest, Neck, Head | Standard FK chain |
| Left arm | ShoulderL, UpperArmL, ForearmL, HandL | |
| Right arm | ShoulderR, UpperArmR, ForearmR, HandR | |
| Left leg | ThighL, ShinL, FootL, ToeL | |
| Right leg | ThighR, ShinR, FootR, ToeR | |
| **IK targets** | IK_HandL, IK_HandR | Used to position hands on club grip |
| **Club socket** | ClubSocket (child of HandR or HandL) | This is where the club mesh attaches |

Use **IK constraints** on both arms so the hands follow the club grip naturally when animating. In Blender, set up IK chains from each hand to the IK target bone (2–3 bone chain length).

#### Armature naming
Name bones in Godot-compatible format (no spaces). Godot's `BoneAttachment3D` node references bones by name — consistent naming prevents breakage when you change the rig.

---

### 2b — Club Meshes

There are **5 club types** in the game (from `ClubDefinition.ClubType`):

| Club | Type | Visual shape | Swing style |
|---|---|---|---|
| Driver | WOOD | Long shaft, large rounded head | Wide flat arc |
| 5-Iron | IRON | Medium shaft, angled blade head | Medium steep arc |
| Hybrid | HYBRID | Medium shaft, rounded iron-style head | Medium arc |
| Pitching Wedge | WEDGE | Short shaft, high-loft angled head | Short steep arc |
| Putter | PUTTER | Short shaft, flat rectangular head | Short pendulum |

#### Model each club separately
- Shaft length: Driver ~1.1 m, Iron ~0.95 m, Putter ~0.85 m
- Keep poly count low: 100–300 tris per club
- **Origin point**: Place the origin at the top of the grip (where the hands hold it) — this is the attachment point to `ClubSocket`

#### How clubs attach in Godot
In Godot, add a `BoneAttachment3D` node as a child of the character's skeleton, set it to the `ClubSocket` bone. The club MeshInstance3D is then a child of the BoneAttachment3D:
```
Character (Node3D)
  └── Skeleton3D
        └── BoneAttachment3D  [bone: ClubSocket]
              └── MeshInstance3D  (active club mesh)
```
Swap the visible club by hiding/showing the appropriate child mesh, or by changing the mesh resource at runtime when the player selects a different club.

---

### 2c — Animation List

The swing is driven by the `SwingState` machine in `scripts/swing_state.gd`. Its phases map directly to character animation states.

#### Game states that drive animation

| Game state | SwingState phase | Character animation |
|---|---|---|
| Waiting for turn | — | `idle` |
| Turn starts, free aim | — | `address` |
| Player presses shoot | `POWER_FILL` starts | `backswing` (seek, not play) |
| Player holds past 100% | `POWER_FILL` overshooting | `backswing` locked at top + shake |
| Player releases | `COMPLETE` fires | `downswing` → `follow_through` |
| Ball in flight | ball simulating | hold `follow_through` |
| Ball at rest | `ball_at_rest` signal | transition back to `address` or `idle` |

---

#### Animation specs

**`idle`**
- Duration: 2–4 s, looping
- Character stands casually to the side of the ball position, club resting on ground
- Subtle weight shift or breathing movement

**`address`**
- Duration: 0.3–0.5 s, **not looping** (plays once then holds last frame)
- Character moves into setup stance: feet shoulder-width apart, slight knee bend, leaning toward ball, both hands on club grip, club head behind the ball
- This is the held pose during free aim

**`backswing`**
- Duration: 1.0 s total (the full 0% → 100% range)
- **This animation is NOT played at normal speed.** It is **seeked** by code using `swing.get_power_normalized()` (0.0–1.0) each frame. See code hook below.
- At t=0.0: address/setup position (club behind ball)
- At t=0.5: club parallel to ground on the way up
- At t=1.0: full backswing top — club above shoulder, coiled torso
- Make sure it flows smoothly as a positional/rotational curve — no snapping

**`downswing`**
- Duration: **0.2–0.25 s** (fast — a real downswing is ~0.2 s)
- Plays immediately after `backswing`, triggered by player releasing
- Club comes down, impact frame at ~0.15 s where the club head is at ball position
- Hips rotate through first, then shoulders, then arms — this is the key to it looking real
- At the impact frame, the club head should be at approximately **ball position** (`Vector3(0, 0, ~1.0)` in character-local space along the aim axis)

**`follow_through`**
- Duration: 0.5–0.8 s, **holds last frame** (don't loop)
- Club continues upward after impact, finishing high on the left side for a right-handed golfer
- Character weight shifts to front foot, head turns to watch the ball

**`walk_to_ball`** *(optional, lower priority)*
- Duration: variable (driven by distance)
- Simple walk cycle the character plays while repositioning to the ball's new rest position between shots
- The easiest way to implement: just blend/teleport the character to the new position and skip a walk animation until the rest of the game is working

---

#### Putter-specific animations (separate set)
The putter has a completely different motion — a short pendulum stroke, not a full swing. Model this as a separate animation set:

| Animation | Notes |
|---|---|
| `address_putt` | Crouched over ball, very close, blade behind ball |
| `backswing_putt` | Short pendulum back, 0.3 m max arc |
| `downswing_putt` | Short pendulum through, very slow (0.3 s) |
| `follow_through_putt` | Blade follows ball direction |

Detect which set to use based on `selected_club.club_type == ClubDefinition.ClubType.PUTTER`.

---

### 2d — Character Positioning (where it stands relative to the ball)

The character should be positioned **behind the ball along the aim axis**, slightly offset to the side (realistic golfer stance):

```
      [cup direction →]
           aim →
  [char]  [ball]
```

In `golf_ball.gd` world space, the character's position is approximately:
```
character.position = ball.global_position
    - aim_direction * 1.2   # 1.2 m behind the ball along aim
    + aim_direction.cross(Vector3.UP) * 0.3  # slight side offset for right-handed stance
```

The character's forward direction (`-Z` in Godot) should face the aim direction:
```
character.look_at(ball.global_position + aim_direction * 10.0, Vector3.UP)
```

During **free aim** (player is rotating the camera/aim), the character should smoothly rotate to track the aim direction each frame. Use `lerp_angle` or `basis.slerp` for smoothness.

---

### 2e — Code Hook (where to add this in golf_ball.gd)

The character Node3D should be a sibling of the ball (not a child — the ball moves, the character stays at the shot position during flight). Add it in `main.gd` when a hole is set up.

In `golf_ball.gd`, add a reference and drive it from these existing hooks:

```gdscript
## Reference to the character node — set by Main
var character: Node3D = null

## In _process() / _handle_club_cycling() area, during free aim:
func _update_free_aim_ui() -> void:
    # ... existing code ...
    _update_character_aim()

func _update_character_aim() -> void:
    if not character:
        return
    # Reposition and rotate character to face aim direction
    character.global_position = global_position - aim_direction * 1.2 \
        + aim_direction.cross(Vector3.UP) * 0.3
    character.look_at(global_position + aim_direction * 10.0, Vector3.UP)

    # Drive backswing seek during POWER_FILL
    if swing.phase == SwingState.Phase.POWER_FILL:
        var anim_player = character.get_node("AnimationPlayer")
        anim_player.play("backswing")
        anim_player.seek(swing.get_power_normalized() * BACKSWING_DURATION, true)

## Connect to swing.swing_complete in _ready() or setup():
## swing.swing_complete.connect(_on_swing_complete)
func _on_swing_complete(_outcome: SwingState.SwingOutcome) -> void:
    if character:
        var anim_player = character.get_node("AnimationPlayer")
        anim_player.play("downswing")
        # follow_through plays automatically via AnimationPlayer queue:
        anim_player.queue("follow_through")
```

The constant `BACKSWING_DURATION` should match exactly the duration of the `backswing` animation clip you export (e.g. `1.0` for a 1-second clip).

---

### 2f — AnimationTree (recommended over raw AnimationPlayer)

For smooth blending between states, use a Godot **AnimationTree** with a **StateMachine**:

```
idle ──→ address ──→ backswing ──→ downswing ──→ follow_through ──→ idle
                  ↑_____________________________________↑
                        (if shot cancelled)
```

- `idle → address`: triggered by `_turn_active = true`
- `address → backswing`: triggered by `swing.phase == POWER_FILL`
- `backswing`: use `AnimationNodeStateMachinePlayback.travel()` + `seek()` to scrub by power
- `backswing → downswing`: triggered by `swing.phase == COMPLETE`
- `downswing → follow_through`: automatic (when downswing finishes)
- `follow_through → idle`: triggered by `ball_at_rest` signal

This is more setup work than raw AnimationPlayer but gives much cleaner transitions and avoids animation pops.

---

### 2g — Export from Blender

Export the character and all animations as a **single .glb file** with everything embedded:

1. Select the character mesh + armature
2. File → Export → glTF 2.0
3. Settings:
   - **Include: Selected Objects** ✓ (mesh + armature only)
   - **Transform: +Y Up** ✓
   - **Geometry: Apply Modifiers** ✓
   - **Animation: NLA Strips** ✓ — each action in the NLA editor becomes a named animation clip in Godot
   - **Animation: Export all armature objects** ✓
4. Name the file `character.glb`, place at `assets/models/character.glb`

In Blender's NLA editor, make sure each animation is its own NLA strip/action with a clear name matching the list above (`idle`, `address`, `backswing`, etc.).

In Godot's import settings for the .glb: set **Loop Mode** on `idle`, `address` (hold), and `follow_through` (hold). Mark `backswing`, `downswing` as non-looping.

---

### 2h — Club export

Export each club as its own .glb:
- `assets/models/clubs/club_driver.glb`
- `assets/models/clubs/club_iron.glb`
- `assets/models/clubs/club_hybrid.glb`
- `assets/models/clubs/club_wedge.glb`
- `assets/models/clubs/club_putter.glb`

The club origin must be at the **grip top** (where hands wrap around). In Godot, attach to `BoneAttachment3D` on the `ClubSocket` bone — the grip top will then sit exactly at the hand position.

---

## Asset 3 — Flag & Cup

### What to model
Two separate objects: a **flag** (cloth triangle on a pole) and a **cup liner** (optional cylinder to make the hole look like a real cup). The pole base sits at terrain height.

### Dimensions
| Part | Size |
|---|---|
| Pole height | 2.0 m |
| Pole radius | 0.02 m |
| Flag (cloth) | ~0.5 m wide × 0.3 m tall |
| Cup liner | r=0.4 m × 0.4 m tall |

### Blender approach

**Pole**: Simple cylinder, tall and thin.

**Flag cloth**: Model as a flat quad/plane, then use Cloth simulation or shape keys to give it a wave. For the cloth wave animation:
1. Create a plane (~8×6 grid divisions) for the flag
2. Attach an Armature with 3–4 bones running left to right (pole-end locked, tip bones animated)
3. Animate the bones in a gentle 2-second wave cycle using keyframes
4. Bake the animation to the NLA editor as an action called `flag_wave`

**Cup liner**: Optional. Simple open cylinder, black material, no top face. Placed at the cup depression position.

### Materials
| Part | Settings |
|---|---|
| Pole | White, metallic=0.3, roughness=0.4 |
| Flag cloth | CLAY red (#692c2c), roughness=0.8 |
| Cup liner | Near-black, roughness=1.0 |

### How to hook it in
Currently `_build_cup_visual()` in `procedural_hole.gd` builds everything from primitives. To replace:
1. Export flag + pole as a single .glb with the `flag_wave` animation
2. In Godot, modify `_build_cup_visual()` to instantiate your .glb scene instead of the procedural code:
```gdscript
var flag_scene = preload("res://assets/models/flag.glb")
var flag_instance = flag_scene.instantiate()
flag_instance.position = Vector3(0, depression_depth, 0)
_cup_area.add_child(flag_instance)
# Start the animation
flag_instance.get_node("AnimationPlayer").play("flag_wave")
```
3. Remove or keep the black cup cylinder — the cup Area3D detection is separate and stays

---

## Asset 3 — Trees (per biome)

The game places trees procedurally in all biomes. Currently they are all the same generic cone+cylinder. Each tree is placed with:
- `obs.radius` — collision cylinder radius (0.5–1.5 m typically)
- `obs.height` — total tree height (3–8 m typically)

Make **3 tree variants** for the 3 base biomes. All trees should work at the sizes above.

### Meadow Tree — Deciduous (oak-like)
- Trunk: tapered cylinder, bark texture
- Canopy: several overlapping sphere clusters or a rounded blob
- Colors: brown bark, medium green leaves
- Poly count: 300–600 tris

### Canyon / Ascending Canyon Tree — Pine or Dead Tree
- Option A: Pine — cone-shaped silhouette, layered branches
- Option B: Scraggly dead tree — bare branches, no leaves, dramatic shape
- Colors: dark bark, muted brown-grey if dead
- Poly count: 400–800 tris

### Desert / Oasis Desert Tree — Cactus or Palm
- Option A: Cactus — central tall column, two side arms
- Option B: Desert palm — thin trunk, fan of spiky fronds at the top
- Colors: dull green/grey cactus, or sandy trunk + dark green fronds
- Poly count: 200–500 tris

### How to hook them in
Modify `_build_tree()` in `scripts/procedural_hole.gd` to load a scene instead of building meshes:

```gdscript
func _build_tree(obs: HoleGenerator.ObstacleDescriptor) -> void:
    var body := StaticBody3D.new()

    # Collision stays exactly as-is
    var col := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = obs.radius
    shape.height = obs.height
    col.shape = shape
    body.add_child(col)

    # Replace the old trunk/foliage code with a loaded scene:
    var tree_scene = _get_tree_scene_for_biome()  # returns preloaded PackedScene
    var tree_mesh := tree_scene.instantiate()
    # Scale to match the procedural sizing
    tree_mesh.scale = Vector3(obs.radius * 1.5, obs.height / REFERENCE_HEIGHT, obs.radius * 1.5)
    body.add_child(tree_mesh)

    var base_y: float = _terrain_height_at(obs.world_position.x, obs.world_position.z)
    body.position = Vector3(obs.world_position.x, base_y + obs.height * 0.5, obs.world_position.z)
    add_child(body)
```

You'll need to add a `_get_tree_scene_for_biome()` helper that checks `layout.terrain_data.biome.biome_name` and returns the right preloaded scene.

### Important: model the tree centered at origin, Y=0 at base
The code places the body at `base_y + height * 0.5`, so the tree mesh origin should be at the **vertical center** of the tree, with the trunk base at `Y = -height/2`.

---

## Asset 4 — Rock Boulders (Rock Slide Hazard)

The rock slide creates 3 boulders (SphereMesh r=0.8) that animate across the fairway.

### What to model
An irregular **boulder mesh** — lumpy, asymmetric rock, roughly 0.6–1.0 m radius. Make 2–3 shape variants to swap in for variety.

### Blender approach
1. Start from an Icosphere (2 subdivisions)
2. Apply a Displace modifier with a procedural noise texture (Scale ~1.5, Strength ~0.3) to break the perfect sphere
3. Apply the modifier and go into Edit Mode to hand-tweak vertices for a chunkier rock look
4. Shade Smooth

### Material
- **Canyon/Desert boulder**: sandy red-brown (#8d8556 → #606c38 range), roughness=0.9, slight bump
- **Meadow boulder**: grey-brown, roughness=0.85

### How to hook it in
In `scripts/hazards/rock_slide_hazard.gd`, `_build_visuals()` currently does:
```gdscript
var sphere := SphereMesh.new()
sphere.radius = 0.8
```
Replace with a loaded mesh resource:
```gdscript
var boulder_scene := preload("res://assets/models/boulder.glb")
# pass to HazardProjectileGroup.setup() — you may need to adapt that class
# to accept a PackedScene instead of a Mesh
```
Check `scripts/utility/` for `HazardProjectileGroup` — it accepts a Mesh and Material. You can either adapt it to accept a PackedScene, or extract the MeshInstance3D's mesh from the imported .glb.

---

## Asset 5 — Decorative Scenery Props (Lower Priority)

These are non-interactive background objects for visual richness. They don't need collision.

### What to make

| Prop | Biomes | Notes |
|---|---|---|
| Rock cluster (small) | Canyon, Desert | 3–5 small rocks grouped |
| Grass tufts | Meadow | Low flat cluster of grass blades |
| Cactus variants | Desert | 1-arm, 2-arm, barrel cactus |
| Fallen log | Meadow, Canyon | Rotting log on ground |
| Dry shrub | Desert, Canyon | Scraggly low bush |
| Sand ripples / dune crest marker | Desert | Flat low-poly ridge shape |

### Dimensions
All props should be **1–3 m tall** max, **0.5–4 m wide**.

### How to hook them in
The game doesn't currently place decorative props. Adding them requires:
1. Add `PROP` to `ObstacleDescriptor.Type` enum in `scripts/hole_generator.gd`
2. Have `HoleGenerator` spawn them in `_generate_obstacles()` using biome-controlled density
3. Add `_build_prop()` to `procedural_hole.gd` that instantiates the scene without collision

This is a low-priority feature — design it only after the core assets are done.

---

## Asset 6 — Water & Lava Surface Materials

These are flat planes built in code — no mesh needed. They need animated **ShaderMaterial** resources.

### Water
Create a ShaderMaterial (or use Godot's `StandardMaterial3D` + normal map) with:
- Albedo: transparent blue (Color(0.1, 0.3, 0.65, 0.55))
- Normal map: animated tiling water normals (can be a Blender-rendered flipbook or use a wave shader)
- Roughness: 0.1 (reflective)
- Transparency: enabled

A simple approach: create a 512×512 normal map tile of water ripples in Blender's texture baker, then animate via UV scroll in a ShaderMaterial.

### Lava
- Albedo: animated orange-red with emissive glow
- Use a Blender-baked lava flow texture (orange/black voronoi pattern) with UV scroll
- Emission: enabled, intensity 1.5–2.0
- Normal: optional rock/lava surface normal

### How to hook them in
In `procedural_hole.gd`, `_add_hazard_plane()` currently creates a `StandardMaterial3D` inline.
Replace it with `preload("res://assets/materials/water.tres")` / `lava.tres` — just create the `.tres` material resources in Godot and reference them there.

---

## Asset 7 — Terrain Textures (ShaderMaterial)

See `docs/asset-plan.md` for full texture specs. This section covers the Blender workflow for baking them.

### Baking tileable textures in Blender
1. Create a plane (2×2 m), apply a Principled BSDF with procedural nodes (Noise, Musgrave, etc.) to match the zone's look
2. Add a second UV-unwrapped plane beneath it as the bake target
3. `Render → Bake → Diffuse Color` — bakes the procedural shader to a 512×512 texture
4. Make seamless: check the texture edges in Blender's Image Editor — use the Clone Stamp tool or export and use GIMP's Tile Seamless filter

### How terrain textures plug in
`BiomeDefinition` has a `material_override: Material` export slot. When set, `TerrainMeshBuilder.create_material()` uses it instead of the default vertex-color material. The terrain mesh has UV coordinates (`world_XZ * uv_scale`).

**Simplest approach** (vertex color + texture detail):
1. Create a `StandardMaterial3D` in Godot
2. Set `vertex_color_use_as_albedo = true`
3. Set a tiling grass/sand/rock texture as the Detail Albedo (under Detail tab)
4. Set Detail Blend Mode to MUL — this tints the texture by the vertex zone color
5. Assign to `material_override` in each biome .tres

**Advanced approach** (per-zone textures, splatmap shader):
Requires a custom GDShader that uses vertex color as zone weights to blend 4–8 different zone textures. This is more work but gives the best result.

---

## File Structure

```
assets/
  models/
    golf_ball.glb
    flag.glb
    cup_liner.glb
    trees/
      tree_meadow.glb
      tree_canyon.glb
      tree_desert.glb
    hazards/
      boulder_a.glb
      boulder_b.glb
    props/
      rock_cluster.glb
      grass_tuft.glb
      cactus_a.glb
      fallen_log.glb
  materials/
    water.tres
    lava.tres
    terrain/
      meadow_terrain.tres
      canyon_terrain.tres
      desert_terrain.tres
  textures/
    terrain/   (see asset-plan.md)
    water_normal.png
    lava_flow.png
```

---

## Animation Reference

| Asset | Animation name | Length | Loop | Notes |
|---|---|---|---|---|
| Flag | `flag_wave` | 2.0 s | Yes | |
| Boulder (optional) | `tumble` | 1.0 s | Yes | |
| Cactus (optional) | none needed | — | — | |
| Character | `idle` | 2–4 s | Yes | Casual waiting pose |
| Character | `address` | 0.3–0.5 s | No — hold last frame | Setup stance |
| Character | `backswing` | 1.0 s | No — **seeked by code** | Drive via `power_normalized` |
| Character | `downswing` | 0.2–0.25 s | No | Plays on shot release |
| Character | `follow_through` | 0.5–0.8 s | No — hold last frame | Plays after downswing |
| Character | `address_putt` | 0.3 s | No — hold | Putter only |
| Character | `backswing_putt` | 0.5 s | No — **seeked by code** | Putter only |
| Character | `downswing_putt` | 0.3 s | No | Putter only |
| Character | `follow_through_putt` | 0.4 s | No — hold | Putter only |

### Playing animations in Godot
When you instantiate a .glb that contains animations, access them via `AnimationPlayer`:
```gdscript
var instance = scene.instantiate()
add_child(instance)
var anim_player = instance.get_node("AnimationPlayer")
anim_player.play("flag_wave")
```

---

## Quick Reference — Key Dimensions

| Object | Scale in Godot | Notes |
|---|---|---|
| Golf ball | r = 0.2 m | Larger than real for gameplay |
| Character | ~1.8 m tall | Humanoid |
| Character offset from ball | ~1.2 m behind, ~0.3 m side | Along aim axis |
| Club (driver) | shaft ~1.1 m | Origin at grip top |
| Club (iron/hybrid) | shaft ~0.95 m | Origin at grip top |
| Club (putter) | shaft ~0.85 m | Origin at grip top |
| Backswing anim duration | 1.0 s | Must match `BACKSWING_DURATION` constant |
| Downswing anim duration | 0.2–0.25 s | Fast — keep it snappy |
| Flag pole | h = 2.0 m, r = 0.02 m | |
| Flag cloth | 0.5 × 0.3 m | Attached at pole top |
| Cup depression | r = varies (1–4 m) | Detection area, not visual size |
| Tree (typical) | h = 3–8 m, r = 0.5–1.5 m | Scales via code, see section 4 |
| Boulder | r ≈ 0.8 m | |
| Terrain | 200–400 m wide, 0–14 m tall | Don't model — procedural |
| Water/lava plane | matches terrain grid size | Don't model — procedural |

---

## Suggested Order of Work

1. **Golf ball** — quick win, always visible, no animation needed
2. **Flag** — high visual impact, easy model, one animation
3. **Meadow tree** — most common biome, biggest visual improvement
4. **Rock boulder** — replaces obvious SphereMesh in hazards
5. **Canyon tree + Desert tree/cactus** — completes biome variety
6. **Water/lava materials** — improve hazard readability
7. **Character (no animations yet)** — model + rig, stub animations, get it placed in scene
8. **Character animations** — `address`, `backswing`, `downswing`, `follow_through`, then `idle`
9. **Club meshes** — model all 5, attach via BoneAttachment3D
10. **Putter-specific animations** — separate animation set for putter club type
11. **Terrain textures** — biggest visual scope, tackle per-biome
12. **Decorative props** — polish pass, requires code changes to place them
