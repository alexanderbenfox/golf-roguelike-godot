# Golf Roguelike — Game Overview

A networked golf game (Mario Golf / Wii Sports Golf style) with roguelike upgrade mechanics, built in Godot 4 with GDScript.

---

## Table of Contents

- [Game Loop](#game-loop)
- [Architecture](#architecture)
- [Player State & Golfer Stats](#player-state--golfer-stats)
- [Shot Mechanics](#shot-mechanics)
- [Physics Simulation](#physics-simulation)
- [Camera System](#camera-system)
- [Procedural Course Generation](#procedural-course-generation)
- [Roguelike Upgrade System](#roguelike-upgrade-system)
- [Meta-Progression](#meta-progression)
- [Network Architecture](#network-architecture)
- [Scoring](#scoring)
- [File Reference](#file-reference)

---

## Game Loop

```
Lobby
  |
  v
Generate Course (seeded RNG)
  |
  v
+---> Start Hole
|       |
|       v
|     Aiming Phase (turn-based, one player at a time)
|       |
|       v
|     Shot Fired -> Follow Camera tracks ball
|       |
|       v
|     Ball Simulating (deterministic physics)
|       |
|       +---> Out of Bounds? -> Teleport back, re-aim
|       |
|       v
|     Ball at Rest -> Show distance to pin
|       |
|       v
|     Ball in Cup? --no--> Next turn / re-aim
|       |
|      yes
|       |
|       v
|     Hole Complete UI (strokes, par, score name)
|       |
|       v
|     Upgrade Screen (pick 1 of 3 upgrades)
|       |
|       v
+--- Next Hole (or Course Complete)
```

---

## Architecture

The game uses a layered architecture with five conceptual layers:

| Layer | Responsibility | Key Files |
|-------|---------------|-----------|
| **State** | Pure data — no Godot dependencies | `state/game_state.gd`, `state/player_state.gd`, `state/hole_state.gd` |
| **Network** | Multiplayer transport, RPCs, peer management | `scripts/managers/network_manager.gd` |
| **Turn** | Server-authoritative turn sequencing | `scripts/managers/turn_manager.gd` |
| **Simulation** | Deterministic physics, shot execution | `physics_simulator.gd`, `golf_ball.gd` |
| **Presentation** | Camera, UI, procedural visuals | `camera_3d.gd`, `scripts/procedural_hole.gd`, `scripts/ui/*` |

`scripts/main.gd` is the **scene coordinator** — it wires all managers together via signals and owns the Godot scene tree interactions (spawning holes, resetting the ball, showing UI).

### Signal Flow for a Shot

```
Player input (hold/release golf_shoot)
  -> golf_ball.shot_ready(direction, power)
  -> main._on_shot_ready()
  -> network_manager.submit_shot()
  -> [server validates] -> network_manager broadcasts
  -> main._on_shot_received()
  -> golf_ball.play_shot(direction, power)
  -> [physics simulation runs]
  -> golf_ball.ball_at_rest(peer_id)
  -> turn_manager.notify_ball_at_rest()
```

---

## Player State & Golfer Stats

### PlayerState (`state/player_state.gd`)

Runtime state for each player during a run:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `peer_id` | `int` | `1` | Network peer identifier |
| `display_name` | `String` | `"Player"` | Shown in UI |
| `ball_position` | `Vector3` | `ZERO` | Current ball position |
| `strokes_this_hole` | `int` | `0` | Strokes on current hole |
| `total_strokes` | `int` | `0` | Cumulative strokes |
| `is_hole_complete` | `bool` | `false` | Whether player has holed out |
| `power_multiplier` | `float` | `1.0` | Shot distance scaling |
| `friction_modifier` | `float` | `1.0` | Ground friction scaling |
| `bounce_modifier` | `float` | `1.0` | Surface bounce scaling |
| `gravity_scale` | `float` | `1.0` | Gravity multiplier (lower = floatier) |
| `accuracy` | `float` | `0.7` | Shot accuracy (0.0 = max spread, 1.0 = perfect) |
| `applied_upgrade_ids` | `Array[String]` | `[]` | Upgrades collected this run |

Serializable via `to_dict()` / `from_dict()` for network transmission.

### GolferStats (`resources/golfer_stats.gd`)

An editor-configurable `Resource` that defines the **starting** values for all modifier stats. Assigned on the Main node in the Inspector. Applies to PlayerState at the start of each run via `apply_to(player)`.

Exposed as `@export_range` fields grouped under Power, Ball Control, Gravity, and Accuracy.

---

## Shot Mechanics

### Aiming

- **Input**: Hold left mouse button (or controller A) to begin aiming
- **Direction**: Derived from the camera's orbit angle (`camera_angle`), not the camera transform — so the lateral aim offset doesn't affect aim direction
- **Power**: Charges linearly while the button is held, clamped to `s_max_power`
- **Mouse capture**: Mouse is captured (`MOUSE_MODE_CAPTURED`) during aiming to prevent cursor leaving the screen; mouse movement rotates the camera orbit
- **Trajectory preview**: A flat arrow ribbon with an arrowhead shows the predicted path, a halo ring marks the landing point, and an accuracy variance cone shows possible spread

### Accuracy Variance

Each shot has random horizontal spread applied before being sent to the network:

```
spread_angle = (1.0 - accuracy) * 0.10 radians
direction = direction.rotated(Vector3.UP, randf_range(-spread, spread))
```

The trajectory preview visualises this spread as two edge lines with a connecting arc at the landing zone.

### Shot Execution

`play_shot(direction, power)` applies `_power_multiplier`, creates an initial velocity, and starts the physics simulation. This method is the network entry point — called on all clients with the same parameters.

---

## Physics Simulation

### PhysicsSimulator (`physics_simulator.gd`)

A custom **deterministic** physics engine (not Godot's built-in RigidBody physics) ensuring identical results across all network clients given the same inputs.

**SimulationState**: position, velocity, time, is_on_ground

**PhysicsParams**: mass, ball_radius, linear_damp, angular_damp, ball_friction, ground_friction, ball_bounce, ground_bounce, gravity_scale, ground_height

Each frame (`simulate_step`):
1. Apply gravity
2. Apply linear damping
3. Integrate position
4. Ground collision — bounce with combined restitution, apply friction to horizontal velocity
5. Check velocity threshold for stop detection

**Obstacle collision** is handled separately in `golf_ball._simulate_step()` using Godot's `move_and_collide()` — velocity is reflected off non-ground surfaces (normal.y < 0.7) with 0.6 restitution.

**Trajectory prediction** (`simulate_trajectory`) runs the full simulation ahead of time to produce an array of positions for the trajectory preview.

### Out of Bounds

Each `ProceduralHole` stores a bounding box around the playable area. The ball checks `is_out_of_bounds(position)` each simulation frame. If OOB (or fallen below y = -5), the ball teleports back to `last_shot_position`.

---

## Camera System

### Camera Modes (`camera_3d.gd`)

| Mode | When | Behaviour |
|------|------|-----------|
| **Orbit** | Default / aiming | Orbits `follow_target` at configurable distance and height. Player controls orbit angle with mouse/stick. |
| **Orbit + Aim Offset** | While aiming | Shifts 2.5 units laterally and 1.5 units higher to reveal the trajectory's parabolic arc. |
| **Follow Shot** | During ball flight | Chase cam positioned behind the ball based on velocity direction. Smoothly tracks with configurable distance/height/look-ahead. |

When transitioning from Follow Shot back to Orbit, `camera_angle` is synced to the current camera position (`atan2(offset.x, offset.z)`) to avoid a jarring jump.

### Distance to Pin

When the ball comes to rest, a "X.Xm to pin" label appears at the bottom of the screen. Hidden when the next shot starts or if the ball is within 1m of the cup.

---

## Procedural Course Generation

### Course Flow

1. `CourseManager.generate_course(seed)` creates a seeded `RandomNumberGenerator`
2. Single RNG pass generates pars AND `HoleLayout` objects together (ensuring determinism across clients)
3. Each hole is built at runtime by `ProceduralHole.build(layout)`

### HoleGenerator (`scripts/hole_generator.gd`)

Pure data generator producing `HoleLayout` objects:

- **Direction**: Random angle scaled by `direction_variety`
- **Length**: Par-based (par 3: 40–80m, par 4: 80–160m, par 5: 160–240m) scaled by `length_multiplier`
- **Fairway width**: 8–14m base, scaled by `fairway_width_scale`
- **Obstacles**: Tree pairs along the fairway (`tree_density`), green bunkers (0–2 x `bunker_density`), optional fairway bunker

### HoleGenConfig (`scripts/hole_gen_config.gd`)

A `Resource` with `@export_range` fields for all generation parameters. Static presets:

| Preset | Length | Width | Trees | Bunkers |
|--------|--------|-------|-------|---------|
| `easy()` | 0.8x shorter | 1.3x wider | 0.5x fewer | 0.3x fewer |
| `medium()` | 1.0x default | 1.0x default | 1.0x default | 1.0x default |
| `hard()` | 1.3x longer | 0.7x narrower | 1.5x denser | 1.8x denser |

### ProceduralHole (`scripts/procedural_hole.gd`)

Builds 3D geometry from a `HoleLayout`:

- **Terrain**: Fairway (PlaneMesh), green (CylinderMesh disc), tee box (PlaneMesh)
- **Ground collision**: StaticBody3D + BoxShape3D sized to `(fairway_width + 60) x (hole_length + 40)`, ensuring the ball never falls through
- **Trees**: StaticBody3D + CylinderShape3D collision + trunk/foliage meshes
- **Bunkers**: Visual discs (friction penalty is a future TODO)
- **Cup**: Area3D + CylinderShape3D, flag pole, red flag; emits `ball_entered_cup`

---

## Roguelike Upgrade System

### Upgrade Resources

Upgrades are fully data-driven — designers create `.tres` files with no code needed:

**UpgradeEffect** (`resources/upgrade_effect.gd`):
- `stat`: POWER, FRICTION, BOUNCE, ACCURACY, or GRAVITY
- `operation`: MULTIPLY or ADD
- `value`: float (e.g., 1.2 for +20% multiply, or 0.5 for flat add)

**UpgradeDefinition** (`resources/upgrade_definition.gd`):
- `id`, `display_name`, `description`
- `rarity`: COMMON, UNCOMMON, or RARE
- `min_meta_level`: minimum meta-progression level to appear in the pool
- `effects`: `Array[UpgradeEffect]` — one or more stat modifications
- `apply(player)`: applies all effects to a PlayerState
- `get_effects_summary()`: human-readable string for UI cards

### UpgradeRegistry (`scripts/managers/upgrade_registry.gd`)

Autoload singleton that auto-discovers all `.tres` files in `res://resources/upgrades/` at startup. Provides `roll_choices(meta_level, count)` which:

1. Filters upgrades by `min_meta_level <= meta_level`
2. Weights by rarity (COMMON: 60%, UNCOMMON: 30%, RARE: 10%)
3. Returns `count` (default 3) random, non-duplicate choices

### Upgrade Screen (`scripts/ui/upgrade_screen.gd`)

Full-screen overlay shown between holes. Presents upgrade cards with rarity-coloured borders, name, description, and stat summary. Player clicks a card to select. Emits `upgrade_selected(upgrade)`.

### Included Upgrades

| ID | Name | Rarity | Effects | Meta Level |
|----|------|--------|---------|------------|
| `pow_driving_range` | Driving Range | Common | +20% Power | 0 |
| `pow_long_drive` | Long Drive | Uncommon | +35% Power | 0 |
| `pow_titan_driver` | Titan Driver | Rare | +55% Power | 2 |
| `fric_smooth_roll` | Smooth Greens | Common | -20% Friction | 0 |
| `fric_iron_control` | Iron Control | Uncommon | +30% Friction | 0 |
| `bounce_rubber_ball` | Rubber Ball | Common | +40% Bounce | 0 |
| `bounce_dead_drop` | Dead Drop | Common | -50% Bounce | 0 |
| `all_golden_club` | Golden Club | Rare | +15% Power, -10% Friction, +15% Bounce | 1 |

---

## Meta-Progression

### MetaProgression (`scripts/managers/meta_progression.gd`)

Autoload singleton that persists across runs via `user://meta_progression.cfg`:

| Field | Description |
|-------|-------------|
| `meta_level` | Current progression level (unlocks higher-tier upgrades) |
| `total_runs` | Total runs completed |
| `total_holes` | Total holes completed across all runs |

**Level thresholds**: Level 1 at 10 holes, Level 2 at 30 holes, Level 3 at 60 holes, etc.

`on_hole_complete()` increments `total_holes` and recalculates level. `on_run_complete()` increments `total_runs`. Both auto-save.

---

## Network Architecture

### Design Principles

- **Server-authoritative**: The host validates all actions; clients never modify game state directly
- **Shot-based sync**: Golf is turn-based, so only `{direction, power}` need to be sent per shot — no per-frame physics streaming
- **Deterministic simulation**: All clients run the same `PhysicsSimulator` with the same inputs, producing identical results
- **Seeded generation**: A single RNG seed produces identical courses on all clients

### NetworkManager (`scripts/managers/network_manager.gd`)

Wraps Godot's `MultiplayerAPI` + ENet:

- `host_game(port)` / `join_game(address, port)` / `setup_singleplayer(name)`
- **Player registration**: `_request_player_info` / `_register_player` / `_sync_player_list` RPCs
- **Shot flow**: `submit_shot()` → `_rpc_submit_shot` (any_peer → server) → `_broadcast_shot()` → `_rpc_broadcast_shot` (authority → all) → emits `shot_received`
- **Game start**: `server_start_game()` / `server_advance_turn()`

### Single-Player Through the Same Stack

`setup_singleplayer()` skips ENet peer creation. `multiplayer.get_unique_id()` returns `1` in offline mode, so all server-authority checks still work without special-casing.

### TurnManager (`scripts/managers/turn_manager.gd`)

Server-authoritative turn sequencing:

- `start_hole(tee_position)` — resets all players, sorts turn order by total strokes
- `notify_ball_at_rest(peer_id)` — advances to the next player's turn
- `notify_player_holed_out(peer_id)` — marks player complete, checks if all done
- Signals: `turn_started(peer_id)`, `hole_complete`

---

## Scoring

### ScoringManager (`scripts/managers/scoring_manager.gd`)

Tracks strokes per hole and cumulative totals. Provides golf scoring classification:

| Score vs Par | Name |
|-------------|------|
| -3 | Albatross |
| -2 | Eagle |
| -1 | Birdie |
| 0 | Par |
| +1 | Bogey |
| +2 | Double Bogey |
| +3 | Triple Bogey |
| +4 or more | +N |

Emits `hole_completed(strokes, par, score_name)` which triggers the hole complete UI.

---

## File Reference

```
golf-roguelike-godot/
|-- state/
|   |-- game_state.gd          # Central game state (phase, players, turn order)
|   |-- player_state.gd        # Per-player data (position, score, modifiers)
|   |-- hole_state.gd          # Per-hole layout data
|
|-- scripts/
|   |-- main.gd                # Scene coordinator
|   |-- hole_generator.gd      # Pure hole layout generation algorithm
|   |-- hole_gen_config.gd     # Generation parameter Resource
|   |-- procedural_hole.gd     # Builds 3D hole geometry from layout
|   |
|   |-- managers/
|   |   |-- network_manager.gd   # Multiplayer transport + RPCs
|   |   |-- turn_manager.gd      # Server-authoritative turn sequencing
|   |   |-- course_manager.gd    # Course generation + hole progression
|   |   |-- scoring_manager.gd   # Stroke tracking + par classification
|   |   |-- upgrade_registry.gd  # Auto-discovers and serves upgrades
|   |   |-- meta_progression.gd  # Persistent cross-run progression
|   |
|   |-- ui/
|   |   |-- upgrade_screen.gd    # Between-hole upgrade selection
|   |   |-- hole_complete_ui.gd  # Post-hole score display
|   |   |-- lobby_ui.gd          # Pre-game lobby
|   |
|   |-- utility/
|       |-- trajectory_drawer.gd # Arrow ribbon, halo, variance cone
|
|-- resources/
|   |-- golfer_stats.gd         # Starting stat defaults Resource
|   |-- upgrade_definition.gd   # Upgrade data Resource
|   |-- upgrade_effect.gd       # Single stat modification Resource
|   |-- default_golfer_stats.tres
|   |-- base_hole_gen_config.tres
|   |-- upgrades/               # .tres files for each upgrade
|
|-- golf_ball.gd                # Ball input, simulation, signals
|-- physics_simulator.gd        # Deterministic physics engine
|-- camera_3d.gd                # Orbit + follow-shot camera
```
