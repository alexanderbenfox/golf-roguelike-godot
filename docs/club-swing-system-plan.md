# Golf Club & Swing Type System — Design Plan

## Context

The current shot system is one-size-fits-all: every shot uses the same hardcoded launch angle (Y=0.5), the same power curve, and the same physics parameters. There's no club selection, no distinction between a tee drive and a green putt, and no skill expression in the swing itself. This plan adds:

1. **Club system** — each club produces distinct ball flight (loft, power, accuracy, landing behavior)
2. **Three-press swing timing** — Mario Golf-style skill check separating power control from accuracy
3. **Terrain-preview power meter** — shows what zone the ball lands in at each power level (Super Battle Golf-style)
4. **Angle control** — player adjusts launch angle within each club's min/max range

---

## Architecture Overview

```
ClubDefinition (Resource)     <- club stats, swing speeds, angle range
        |
SwingState (runtime)          <- tracks three-press phases, overshoot, accuracy result
        |
GolfBall.setup_physics_params()  <- applies club + upgrades + swing result to PhysicsParams
        |
PhysicsSimulator / TrajectoryDrawer  <- uses modified params (no changes needed)
```

**Stat flow with clubs + swing:**
```
ClubDefinition (base values)
    x PlayerState modifiers (roguelike upgrades, multiplicative)
    x SwingResult (accuracy deviation from timing, overshoot penalty)
    -> PhysicsParams (used by simulation + trajectory preview)
```

---

## ClubDefinition Resource

`resources/club_definition.gd`:

```gdscript
class_name ClubDefinition
extends Resource

enum ClubType { WOOD, IRON, HYBRID, WEDGE, PUTTER }

@export var id: String = ""
@export var display_name: String = ""
@export var club_type: ClubType = ClubType.IRON

# -- Shot shape --
## Multiplier on max shot power. Driver = 1.0 (full), Putter = 0.15.
@export_range(0.0, 2.0) var power_scale: float = 1.0

# -- Angle (replaces old loft field) --
## Minimum launch angle in degrees.
@export_range(0.0, 90.0) var min_angle_deg: float = 20.0
## Maximum launch angle in degrees.
@export_range(0.0, 90.0) var max_angle_deg: float = 35.0
## Default launch angle when club is first selected.
@export_range(0.0, 90.0) var default_angle_deg: float = 28.0

# -- Swing timing --
## How fast the power indicator fills (percent per second). Higher = faster.
@export_range(1.0, 15.0) var swing_fill_speed: float = 5.0
## How fast the accuracy indicator returns (percent per second). Higher = harder.
@export_range(1.0, 15.0) var swing_return_speed: float = 7.0
## Multiplier on sweet spot width. Higher = more forgiving.
@export_range(0.3, 3.0) var sweet_spot_scale: float = 1.0

# -- Landing behavior --
## Multiplier on ball bounce at landing. Low = ball stops faster. Wedge ~0.3, Driver ~1.0.
@export_range(0.0, 2.0) var landing_bounce: float = 1.0
## Extra friction applied while ball is rolling after this club's shot.
@export_range(0.0, 3.0) var landing_friction: float = 1.0

# -- Auto-selection hints --
## Minimum distance to pin (metres) where this club is suggested.
@export var suggest_min_distance: float = 0.0
## Maximum distance to pin where this club is suggested.
@export var suggest_max_distance: float = 999.0
## Zone types where this club is auto-suggested (e.g., putter on GREEN).
@export var suggest_zones: Array[int] = []  # TerrainData.ZoneType values
```

---

## Default Club Bag (5 clubs — one per category)

| Club | Type | Power | Angle (min/def/max) | Fill Speed | Return Speed | Sweet Spot | Landing Bounce | Landing Friction | Distance Range | Notes |
|------|------|-------|---------------------|-----------|-------------|------------|----------------|------------------|---------------|-------|
| **Driver** | WOOD | 1.0 | 8/12/18° | 6.0 | 10.0 | 0.7 | 1.0 | 0.8 | 120m+ | Fast swing, tiny sweet spot — hardest to hit |
| **5-Iron** | IRON | 0.65 | 20/28/35° | 5.0 | 7.0 | 1.0 | 0.8 | 1.0 | 50-140m | Balanced all-rounder |
| **Hybrid** | HYBRID | 0.80 | 15/20/28° | 5.5 | 6.0 | 1.1 | 0.9 | 0.9 | 80-170m | Slightly forgiving long club |
| **Pitching Wedge** | WEDGE | 0.40 | 38/45/55° | 4.0 | 5.0 | 1.2 | 0.3 | 2.0 | 0-80m | Slow, precise, stops fast |
| **Putter** | PUTTER | 0.15 | 0/2/5° | 2.5 | 3.0 | 1.5 | 0.05 | 1.5 | 0-30m | Very slow, very wide sweet spot |

### Swing behaviour per club type

- **WOOD (Drive)**: Low trajectory, ball launches fast and shallow, bounces several times, rolls far. Maximum distance. Fast swing timing — hardest to nail accuracy.
- **IRON (Approach)**: Medium arc. Moderate bounce and roll. Balanced swing speed.
- **HYBRID**: Between wood and iron — higher than driver, easier to hit (better accuracy than wood at similar distance). Slightly forgiving timing.
- **WEDGE (Chip)**: High arc, ball goes up steeply, lands soft with heavy backspin (high landing_friction, low landing_bounce). Slow swing — easy to time precisely.
- **PUTTER (Putt)**: Ball rolls along the ground with no arc. Very low power for precision distance control. Slowest swing, widest sweet spot.

---

## Swing Timing Mechanic (Three-Press System)

### Overview

Replaces the current hold-to-charge system with three discrete button presses on the shoot input:

```
Press 1: START       — Power indicator begins filling (0% → 100%)
Press 2: SET POWER   — Locks power at current indicator position
Press 3: ACCURACY    — Small timing bar; press in the sweet spot
```

### Phase 1 — Power Fill

- Player presses shoot button. Power indicator begins moving from 0% to 100%.
- Speed determined by `club.swing_fill_speed` (percent per second), modified by player upgrades.
- Trajectory preview updates in real-time as indicator moves.
- Terrain zone bands on the vertical meter show what zone the ball lands in at each power level (see UI section below).
- Player presses shoot again to lock power.

**Overshoot penalty:** If the indicator reaches 100%, it does NOT stop — it bounces back down. When the player eventually presses to lock power, the overshoot distance is tracked:

```gdscript
var overshoot_amount: float = 0.0  # 0.0 = no overshoot, 1.0 = hit 100% and came all the way back to 0%

# Overshoot multiplies inaccuracy in Phase 2:
var inaccuracy_multiplier: float = 1.0 + overshoot_amount * 3.0
# e.g. slight overshoot (0.1) = 1.3x inaccuracy
#      big overshoot (0.5) = 2.5x inaccuracy
```

This punishes overshooting without outright failing the shot — you still get to play, but accuracy suffers. It creates tension as the indicator approaches 100%.

### Phase 2 — Accuracy Return

After power is locked, a small horizontal accuracy bar appears:

- An indicator sweeps from one end to the other at `club.swing_return_speed`.
- A highlighted **sweet spot** is centered on the bar. Its width is determined by:

```gdscript
var base_sweet_spot_width: float = 0.12  # 12% of bar width
var sweet_spot: float = base_sweet_spot_width * club.sweet_spot_scale * player_accuracy_modifier
```

- Player presses shoot a third time. Where the indicator is relative to the sweet spot determines accuracy:

| Hit Zone | Distance from Center | Effect |
|----------|---------------------|--------|
| **Perfect** | Within ±2% (of bar) | No deviation. +5% power bonus. |
| **Good** | Within sweet spot | Minimal deviation: ±2° base × inaccuracy_multiplier |
| **OK** | Within 2× sweet spot | Moderate hook/slice: ±8° base × inaccuracy_multiplier |
| **Miss** | Beyond 2× sweet spot | Heavy hook/slice: ±15° base × inaccuracy_multiplier. -10% power. |

- The deviation direction (hook vs slice) is determined by which side of center the indicator is on when pressed.
- If the player doesn't press at all, the indicator reaches the end and auto-fires as a Miss.

### Phase Flow Diagram

```
[IDLE] ──press──► [POWER FILLING]
                      │
                      │ indicator 0% → 100% (→ bounce back on overshoot)
                      │
                  press ▼
              [POWER LOCKED]
                      │
                      │ accuracy bar appears
                      │ indicator sweeps across
                      │
                  press ▼
              [SHOT FIRED]
                      │
                      ├─ Apply power (locked value × power_scale)
                      ├─ Apply accuracy deviation (from timing result × overshoot multiplier)
                      ├─ Apply angle (from pre-set angle during free aim)
                      └─ Emit shot_ready signal
```

### Auto-Accuracy Upgrade

The roguelike upgrade **"Auto-Caddy"** converts the three-press system to a two-press system:
- Phase 2 (accuracy) is skipped entirely.
- Accuracy result is always "Good" (minimal deviation, no perfect bonus).
- This is a meaningful trade-off: easier shots, but you can never hit "Perfect" for the power bonus.
- Stacks: picking it a second time upgrades auto-accuracy from "Good" to "Perfect".

---

## Angle Control

### Overview

Each club defines a min/max launch angle in degrees. The player adjusts angle during **free aim** (before starting the swing), not during the power fill.

### Input

| Action | Keyboard | Mouse | Controller |
|--------|----------|-------|------------|
| `angle_up` | E / Page Up | Scroll Up | Right Stick Up |
| `angle_down` | Q / Page Down | Scroll Down | Right Stick Down |

Angle adjusts in 1° increments per input. Holding the key repeats at ~8°/sec.

### Conversion from Degrees to Launch Vector

Replaces the old `loft` field:

```gdscript
# Old: aim_direction = Vector3(forward.x, club.loft, forward.z).normalized()
# New:
var angle_rad: float = deg_to_rad(current_angle_deg)
var horizontal: float = cos(angle_rad)
var vertical: float = sin(angle_rad)
aim_direction = Vector3(forward.x * horizontal, vertical, forward.z * horizontal).normalized()
```

### Angle Persistence

- When switching clubs, angle resets to `club.default_angle_deg`.
- Within the same club, angle persists between shots (useful for repeated approaches).
- Roguelike upgrade **"Muscle Memory"** makes angle persist across club switches too.

---

## Terrain-Preview Power Meter

### Concept

A tall vertical bar on the left side of the screen. Along its length, colored bands show what terrain zone the ball would land in at each power level — so the player can see at a glance whether they're aiming into fairway, rough, bunker, or water.

### Computation

When aiming starts and whenever aim direction or angle changes:

1. Sample trajectory at N power levels (every 5% from 5% to 100% = 20 samples).
2. For each sample, run `PhysicsSimulator.simulate_trajectory()` to get the landing position.
3. Query `TerrainData.get_zone_at(landing_x, landing_z)` to get the zone type.
4. Map zone type to the zone's color from `BiomeDefinition.zones[zone_type].color`.
5. Paint that band of the meter with that color.

Cache results; only recompute when direction or angle changes.

**Performance:** 20 trajectory simulations is fine — `simulate_trajectory` already runs every frame for the live preview. Batch them on direction change, not every frame.

### Visual Design

```
     ┌────┐
     │ RR │ 100%  — rough
     │ RR │
     │ FF │       — fairway
     │ FF │
     │ BB │       — bunker
     │ FF │       — fairway
     │ FF │
     │▓▓▓▓│ ← current power indicator (glowing line)
     │ FF │
     │ GG │       — green
     │ GG │
     └────┘
      28°   ← angle display
```

- Bar: ~300px tall, ~40px wide.
- Zone bands use colors from the biome's `ZoneDefinition.color`.
- Small letter abbreviations on each band (F, G, R, B, W, H for hazard, etc.).
- Thin bright horizontal line marks current power indicator position.
- During accuracy phase, the power line is locked and pulses.
- Below the bar: angle display in degrees with up/down arrows hint.

---

## UI Layout (Full HUD During Aiming)

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│  ┌────┐                                              │
│  │ RR │                                              │
│  │ FF │  Terrain-                                    │
│  │ BB │  Preview          [3D VIEWPORT]              │
│  │ FF │  Power                                       │
│  │▓▓▓▓│  Meter                              ┌─────┐ │
│  │ FF │                                     │ 28° │ │
│  │ GG │                                     │ Q/E │ │
│  └────┘                                     └─────┘ │
│                                                      │
│              ┌─────────────────────────┐             │
│              │  <  [ Pitching Wedge ]  >  │          │
│              │    ~70m range • 85m pin    │          │
│              └─────────────────────────┘             │
│                                                      │
│  Phase 2 only:                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  [░░░░░░░░░░░░░▓▓▓██▓▓▓░░░░░░░░░░░░░░░░░░] │    │
│  │                  ▲ sweet spot                │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### Element Breakdown

| Element | Position | Visible When | Purpose |
|---------|----------|-------------|---------|
| **Terrain-preview power meter** | Left | Aiming (all phases) | Strategic info: zone at each power level. Power indicator during Phase 1. |
| **Angle display** | Bottom-right | Free aim + aiming | Current launch angle in degrees. Shows Q/E hint. |
| **Club selector** | Bottom-center | Ball at rest + aiming | Current club name, range, distance to pin. |
| **Accuracy timing bar** | Bottom | Phase 2 only | Horizontal bar for the accuracy press. Appears after power lock, disappears after press. |
| **Trajectory preview** | 3D viewport | Aiming (Phase 1) | Arrow/ribbon showing predicted ball path (existing system). |

### Visibility by Phase

| Phase | Power Meter | Trajectory | Accuracy Bar | Angle Display |
|-------|-------------|-----------|-------------|---------------|
| Free aim (before press 1) | Visible (static) | Visible at default power | Hidden | Visible + editable |
| Power fill (press 1 → press 2) | Indicator moving | Updating in real-time | Hidden | Visible (locked) |
| Accuracy (press 2 → press 3) | Indicator locked, pulsing | Frozen at locked power | Visible + sweeping | Visible (locked) |
| Ball in flight | Hidden | Hidden | Hidden | Hidden |

---

## Club Selection Mechanics

### Input

New input actions:
- `club_next` — Tab / Right Bumper (RB) / D-pad Right
- `club_prev` — Shift+Tab / Left Bumper (LB) / D-pad Left

Cycling is available any time the ball is at rest and it's the player's turn (same conditions as starting a shot). Cycling while in free aim is also allowed — trajectory preview and terrain bands update immediately. Cycling is **disabled** once the swing has started (Phase 1+).

### Auto-Suggestion Logic

When the ball comes to rest, auto-select the best club:

```
distance_to_pin = XZ distance from ball to cup

1. If ball is on GREEN zone -> Putter
2. If ball is in BUNKER zone -> Wedge (or Sand Wedge if unlocked)
3. If ball is on TEE zone -> Driver
4. Otherwise, pick the club whose suggest_min/max_distance range
   best brackets the current distance_to_pin
```

Priority: zone-based suggestions override distance-based. Player can always override with club_next/club_prev.

### Ball state tracking

`GolfBall` gains:
```gdscript
var club_bag: Array[ClubDefinition] = []      # set from PlayerState
var selected_club_index: int = 0               # current selection
var selected_club: ClubDefinition              # convenience getter
var current_angle_deg: float = 28.0            # player-adjusted angle
```

---

## How Clubs + Swing Modify the Physics Pipeline

### Angle to launch vector

```gdscript
# Replaces hardcoded Y=0.5:
var angle_rad: float = deg_to_rad(current_angle_deg)
var horizontal: float = cos(angle_rad)
var vertical: float = sin(angle_rad)
aim_direction = Vector3(forward.x * horizontal, vertical, forward.z * horizontal).normalized()
```

### Power from swing

```gdscript
# Power locked during Phase 1:
var effective_power: float = locked_power_percent * s_max_power * club.power_scale

# Perfect accuracy gives +5% power bonus:
if swing_result == SwingResult.PERFECT:
    effective_power *= 1.05
# Miss gives -10% power penalty:
elif swing_result == SwingResult.MISS:
    effective_power *= 0.90
```

### Accuracy from swing

```gdscript
# Base deviation from accuracy timing (degrees):
var base_deviation_deg: float = swing_deviation_table[swing_result]
# Multiply by overshoot penalty:
var deviation_deg: float = base_deviation_deg * (1.0 + overshoot_amount * 3.0)
# Apply player accuracy modifier (reduces deviation):
deviation_deg /= (player_accuracy * club.sweet_spot_scale)
# Rotate aim_direction horizontally by deviation_deg (+ or - based on timing side):
aim_direction = aim_direction.rotated(Vector3.UP, deg_to_rad(deviation_deg * timing_side))
```

### Landing behavior

```gdscript
sim_params.ball_bounce *= player.bounce_modifier * club.landing_bounce
sim_params.ground_friction *= player.friction_modifier * club.landing_friction
```

No changes needed to PhysicsSimulator or TrajectoryDrawer — they already use PhysicsParams generically.

---

## Integration with Roguelike Upgrades

### Swing Timing Upgrades (new)

| Upgrade | Effect | Rarity | Category |
|---------|--------|--------|----------|
| **Steady Hands** | Sweet spot +25% wider | Common | Accuracy |
| **Quick Draw** | Fill speed +20% (reach full power faster) | Common | Speed |
| **Slow Motion** | Return speed -15% (more time to hit accuracy) | Uncommon | Accuracy |
| **Perfect Form** | "Perfect" zone power bonus increased from +5% to +12% | Uncommon | Power |
| **Forgiving Swing** | "Miss" deviation reduced from ±15° to ±10° | Common | Accuracy |
| **Auto-Caddy** | Skip accuracy phase (always "Good"). Pick again → always "Perfect". | Rare | Special |
| **Power Surge** | Overshoot grace: indicator pauses for 0.3s at 100% before bouncing back | Uncommon | Power |
| **Muscle Memory** | Angle persists across club switches | Common | QoL |
| **Consistent Angle** | Angle persists between holes (doesn't reset) | Common | QoL |

### Global modifiers (existing system, unchanged)

Current upgrades (POWER, FRICTION, BOUNCE, ACCURACY, GRAVITY) continue to work as global multipliers applied to all clubs equally. No upgrade system changes needed for the club system to work.

### Club-specific upgrades (future)

Extend `UpgradeEffect.Stat` enum:
```gdscript
enum Stat {
    POWER, FRICTION, BOUNCE, ACCURACY, GRAVITY,  # existing
    CLUB_ANGLE_RANGE,    # widen min/max angle range
    CLUB_FILL_SPEED,     # modify power fill speed
    CLUB_SWEET_SPOT,     # modify sweet spot width
    CLUB_LANDING_BOUNCE, # modify landing softness
}
```

Add optional club type filter to UpgradeEffect:
```gdscript
## If set, this effect only applies to the specified club type. -1 = all clubs.
@export var club_type_filter: int = -1
```

Example upgrades:
- **"Long Iron"** — +15% power for IRON type clubs only
- **"Soft Touch"** — -30% landing_bounce for WEDGE type (ball stops even faster)
- **"Precision Putter"** — +20% sweet spot for PUTTER only
- **"Wide Arc"** — +10° max angle for WEDGE (can lob even higher)

### Bag upgrades (future)

New upgrade category that adds clubs to the bag:
- **"3-Wood"** — adds a second WOOD club (less power than driver, more accuracy)
- **"Sand Wedge"** — adds a WEDGE optimised for bunkers (lower friction penalty)
- **"Lob Wedge"** — adds a WEDGE with extreme angle (55-70°) for getting over obstacles

These would be separate UpgradeDefinition .tres files with a new effect type:
```gdscript
enum Stat {
    ...,
    UNLOCK_CLUB,  # value = index into a master club registry
}
```

---

## Affected Existing Systems

| System | Change |
|--------|--------|
| **GolfBall** | Club bag, selected club, three-press swing state machine, angle control, launch vector from degrees |
| **PlayerState** | Stores `club_bag: Array[Resource]`, `has_auto_accuracy: bool` |
| **GolferStats** | Default bag configuration (which clubs a new player starts with) |
| **Main** | Passes club bag to ball, auto-suggests club on hole start |
| **PhysicsSimulator** | No changes (reads PhysicsParams generically) |
| **TrajectoryDrawer** | No changes (reads PhysicsParams generically) |
| **ProceduralHole** | Exposes zone at ball position for auto-suggestion + zone at landing for meter |
| **UpgradeEffect** | New Stat entries for swing timing mods |
| **UI (new scenes)** | Terrain-preview power meter, accuracy timing bar, angle display, club selector |

---

## Implementation Phases

| Phase | What | Validates |
|-------|------|-----------|
| **1** | ClubDefinition resource (with angle + swing fields) + default .tres files + GolferStats default bag | Data exists, loads in editor |
| **2** | Angle control: input actions, degree-to-vector conversion, angle display UI | Player can adjust angle, trajectory preview reflects it |
| **3** | Three-press swing state machine in GolfBall (power fill → lock → accuracy → fire) | Swing flow works with placeholder UI |
| **4** | Overshoot penalty (bounce-back at 100%, inaccuracy multiplier) | Overshooting feels punishing but fair |
| **5** | Club affects shot physics (power_scale, angle range, swing speeds, sweet_spot_scale, landing) | Different clubs produce different flights and swing feel |
| **6** | Terrain-preview power meter UI (vertical bar with zone bands) | Player sees what zone they'll land in at each power |
| **7** | Accuracy timing bar UI (horizontal bar, sweet spot highlight, result feedback) | Visual feedback for accuracy phase |
| **8** | Club selection input (cycling) + auto-suggestion based on distance/zone | Player can switch clubs, game suggests appropriate one |
| **9** | Club selector HUD + power meter colour per club type | Visual feedback for selected club |
| **10** | Swing timing upgrades (Auto-Caddy, Steady Hands, Power Surge, etc.) | Roguelike upgrades modify swing feel |
| **11** | Club-specific upgrades (extend UpgradeEffect) | Upgrades can target specific club types |
| **12** | Bag upgrades (unlock new clubs via roguelike progression) | Bag grows over a run |

Each phase is independently testable and the game stays playable throughout. Phases 1-5 are the core mechanic. Phases 6-9 are UI polish. Phases 10-12 are roguelike integration.

---

## New File Structure

```
resources/
    club_definition.gd           # ClubDefinition resource class
    clubs/
        driver.tres              # Default WOOD
        iron_5.tres              # Default IRON
        hybrid.tres              # Default HYBRID
        wedge_pitching.tres      # Default WEDGE
        putter.tres              # Default PUTTER
    golfer_stats/
        (existing default_golfer_stats.tres gains club_bag field)

scripts/
    swing_state.gd               # SwingState machine (three-press phases, timing, results)

scripts/ui/
    club_selector_ui.gd          # HUD widget showing current club + cycling
    terrain_power_meter.gd       # Vertical bar with zone bands + power indicator
    accuracy_timing_bar.gd       # Horizontal bar for accuracy phase
    angle_display.gd             # Angle readout with up/down hint
```

---

## Resolved Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Club vs swing independence** | Paired — club determines swing type | Fewer choices per shot, fits roguelike pacing |
| **Default bag size** | 5 clubs (one per category) | Enough variety without overwhelming; more via upgrades |
| **Launch angle control** | Player adjusts within club's min/max during free aim | Strategic depth: same club can play different shots. Angle locked once swing starts. |
| **Swing system** | Three-press (power fill → lock → accuracy timing) | Separates power and accuracy skill, creates risk/reward tension |
| **Two-press option** | Roguelike upgrade "Auto-Caddy" skips accuracy phase | Meaningful trade-off: easier but can't hit Perfect for power bonus |
| **Overshoot at 100%** | Indicator bounces back; overshoot distance multiplies inaccuracy | Punishes without failing — you still shoot but accuracy suffers |
| **Power meter info** | Terrain zone bands on vertical bar | Gives strategic info (like Super Battle Golf) without adding complexity |
| **Accuracy bar** | Separate horizontal bar, appears only during Phase 2 | Keeps power (strategy) and accuracy (execution) visually distinct |
| **Putter behaviour** | Near-zero angle, slow fill, slow return, huge sweet spot — ground roll | Distinct feel; almost impossible to miss accuracy but precise distance control matters |
| **Upgrade interaction** | Global multipliers first, club-specific later | Phase 1 works with zero upgrade changes |
| **Auto-suggestion** | Zone-based priority, then distance-based | Green -> putter, Tee -> driver, otherwise by range |
| **Bag upgrades** | Unlock new clubs as roguelike upgrade rewards | Gives run-over-run bag growth alongside stat upgrades |
