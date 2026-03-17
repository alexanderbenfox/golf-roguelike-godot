# Golf Club & Swing Type System — Design Plan

## Context

The current shot system is one-size-fits-all: every shot uses the same hardcoded launch angle (Y=0.5), the same power curve, and the same physics parameters. There's no club selection, no distinction between a tee drive and a green putt. This plan adds a club/swing type system where each club produces distinct ball flight — different loft, power, accuracy, and landing behavior — giving players meaningful strategic choice on every shot.

---

## Architecture Overview

One new resource type, following the existing pattern of "pure data first":

```
ClubDefinition (Resource)     <- describes loft, power, accuracy, landing behavior per club
        |
GolfBall.setup_physics_params()  <- applies club + player upgrades to PhysicsParams
        |
PhysicsSimulator / TrajectoryDrawer  <- uses modified params (no changes needed)
```

**Stat flow with clubs:**
```
ClubDefinition (base values)
    x PlayerState modifiers (roguelike upgrades, multiplicative)
    -> PhysicsParams (used by simulation + trajectory preview)
```

The club provides base values, and upgrades multiply on top. Example: Wedge base power = 0.4, player has +20% power upgrade -> effective power = 0.4 x 1.2 = 0.48. Same upgrade benefits all clubs proportionally.

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
## Y component of aim direction vector (before normalization).
## Higher = more loft. Driver ~0.25, Iron ~0.45, Wedge ~0.85, Putter ~0.02.
@export_range(0.0, 1.5) var loft: float = 0.45

## Multiplier on max shot power. Driver = 1.0 (full), Putter = 0.15.
@export_range(0.0, 2.0) var power_scale: float = 1.0

## How fast power charges (seconds to full). Lower = faster. Putter is slow for precision.
@export_range(0.1, 3.0) var charge_rate: float = 1.0

## Base accuracy modifier (multiplied with player accuracy). Putter = 1.3, Driver = 0.8.
@export_range(0.1, 2.0) var accuracy_modifier: float = 1.0

# -- Landing behavior --
## Multiplier on ball bounce at landing. Low = ball stops faster. Wedge ~0.3, Driver ~1.0.
@export_range(0.0, 2.0) var landing_bounce: float = 1.0

## Extra friction applied while ball is rolling after this club's shot. Wedge = high (backspin).
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

| Club | Type | Loft | Power | Charge | Accuracy | Landing Bounce | Landing Friction | Distance Range | Notes |
|------|------|------|-------|--------|----------|----------------|------------------|---------------|-------|
| **Driver** | WOOD | 0.25 | 1.0 | 1.0 | 0.80 | 1.0 | 0.8 | 120m+ | Max distance, lowest accuracy |
| **5-Iron** | IRON | 0.45 | 0.65 | 1.0 | 1.0 | 0.8 | 1.0 | 50-140m | Versatile all-rounder |
| **Hybrid** | HYBRID | 0.35 | 0.80 | 1.0 | 0.95 | 0.9 | 0.9 | 80-170m | Easier long shots |
| **Pitching Wedge** | WEDGE | 0.85 | 0.40 | 0.8 | 1.15 | 0.3 | 2.0 | 0-80m | High arc, stops fast (backspin) |
| **Putter** | PUTTER | 0.02 | 0.15 | 0.5 | 1.30 | 0.05 | 1.5 | 0-30m | Ground roll only, precision |

### Swing behaviour per club type

- **WOOD (Drive)**: Low trajectory, ball launches fast and shallow, bounces several times, rolls far. Maximum distance. Wider accuracy spread.
- **IRON (Approach)**: Medium arc. Moderate bounce and roll. Balanced shot for mid-range.
- **HYBRID**: Between wood and iron — higher than driver, easier to hit (better accuracy than wood at similar distance).
- **WEDGE (Chip)**: High arc, ball goes up steeply, lands soft with heavy backspin (high landing_friction, low landing_bounce). Stops near where it lands.
- **PUTTER (Putt)**: Ball rolls along the ground with no arc. Very low power for precision distance control. Slow charge rate. Highest accuracy. Minimal bounce on contact.

---

## Club Selection Mechanics

### Input

New input actions:
- `club_next` — Tab / Right Bumper (RB) / D-pad Right
- `club_prev` — Shift+Tab / Left Bumper (LB) / D-pad Left

Cycling is available any time the ball is at rest and it's the player's turn (same conditions as starting a shot). Cycling while aiming is also allowed — trajectory preview updates immediately to reflect the new club.

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
```

---

## How Clubs Modify the Physics Pipeline

In `GolfBall.setup_physics_params()`:

```gdscript
# Current: aim_direction = Vector3(forward.x, 0.5, forward.z).normalized()
# New:     aim_direction = Vector3(forward.x, club.loft, forward.z).normalized()

# Current: aim_power clamped to s_max_power (10.0)
# New:     aim_power clamped to s_max_power * club.power_scale

# Current: charge rate = s_charge_rate (1.0)
# New:     charge rate = s_charge_rate * club.charge_rate

# Current: _accuracy = player.accuracy
# New:     _accuracy = player.accuracy * club.accuracy_modifier

# Current: sim_params.ball_bounce *= player.bounce_modifier
# New:     sim_params.ball_bounce *= player.bounce_modifier * club.landing_bounce

# Current: sim_params.ground_friction *= player.friction_modifier
# New:     sim_params.ground_friction *= player.friction_modifier * club.landing_friction
```

No changes needed to PhysicsSimulator or TrajectoryDrawer — they already use PhysicsParams generically. The trajectory preview automatically reflects the selected club because it reads the same params.

---

## UI Design

### Club Selector HUD (bottom-left, always visible when ball is at rest)

```
+-----------------------------+
|  <  [  5-Iron  ]  >        |
|     ~ 130m range            |
|     82m to pin              |
+-----------------------------+
```

- Club name in centre, large text (22px)
- Left/right arrows show cycling is available (dim when at first/last club)
- Approximate range below club name (small text, 14px)
- Distance to pin below that
- Background: semi-transparent dark panel matching existing UI style
- Highlights recommended club with a subtle indicator (star or different colour)
- Hidden while ball is in flight

### Power Meter Enhancement

- Colour coding changes per club type:
  - WOOD: Blue fill
  - IRON: Green fill (current)
  - HYBRID: Teal fill
  - WEDGE: Yellow fill
  - PUTTER: White fill with slower, more granular fill animation

### Trajectory Preview

No structural changes needed — the trajectory naturally changes shape based on club params:
- Driver: long shallow arc
- Wedge: short steep arc
- Putter: flat ground line (loft ~ 0, stays on surface)

---

## Integration with Roguelike Upgrades

### Phase 1: Global modifiers (existing system, unchanged)

Current upgrades (POWER, FRICTION, BOUNCE, ACCURACY, GRAVITY) continue to work as global multipliers applied to all clubs equally. No upgrade system changes needed for the club system to work.

### Phase 2: Club-specific upgrades (future)

Extend `UpgradeEffect.Stat` enum:
```gdscript
enum Stat {
    POWER, FRICTION, BOUNCE, ACCURACY, GRAVITY,  # existing
    CLUB_LOFT,           # modify launch angle
    CLUB_CHARGE_RATE,    # modify charge speed
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
- **"Precision Putter"** — +20% accuracy for PUTTER only

### Phase 3: Bag upgrades (future)

New upgrade category that adds clubs to the bag:
- **"3-Wood"** — adds a second WOOD club (less power than driver, more accuracy)
- **"Sand Wedge"** — adds a WEDGE optimised for bunkers (lower friction penalty)
- **"Lob Wedge"** — adds a WEDGE with extreme loft (0.95+) for getting over obstacles

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
| **GolfBall** | Club bag, selected club, loft/power/charge from club, club cycling input |
| **PlayerState** | Stores `club_bag: Array[Resource]` (ClubDefinition refs) |
| **GolferStats** | Default bag configuration (which clubs a new player starts with) |
| **Main** | Passes club bag to ball, auto-suggests club on hole start |
| **PhysicsSimulator** | No changes (reads PhysicsParams generically) |
| **TrajectoryDrawer** | No changes (reads PhysicsParams generically) |
| **ProceduralHole** | Exposes zone at ball position for auto-suggestion |
| **UpgradeEffect** | Future: new Stat entries for club-specific mods |

---

## Implementation Phases

| Phase | What | Validates |
|-------|------|-----------|
| **1** | ClubDefinition resource + default .tres files + GolferStats default bag | Data exists, loads in editor |
| **2** | Club affects shot physics (loft, power_scale, charge_rate, accuracy, landing) | Different clubs produce different ball flights |
| **3** | Club selection input (cycling) + auto-suggestion based on distance/zone | Player can switch clubs, game suggests appropriate one |
| **4** | Club selector HUD + power meter colour per club type | Visual feedback for selected club |
| **5** | Club-specific upgrades (extend UpgradeEffect) | Upgrades can target specific club types |
| **6** | Bag upgrades (unlock new clubs via roguelike progression) | Bag grows over a run |

Each phase is independently testable and the game stays playable throughout.

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

scripts/ui/
    club_selector_ui.gd          # HUD widget showing current club + cycling
```

---

## Resolved Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Club vs swing independence** | Paired — club determines swing type | Fewer choices per shot, fits roguelike pacing |
| **Default bag size** | 5 clubs (one per category) | Enough variety without overwhelming; more via upgrades |
| **Launch angle control** | Club determines loft, not player | Keeps controls simple; strategic choice is which club |
| **Putter behaviour** | Near-zero loft, slow charge, ground roll | Distinct feel from other clubs; precision putting |
| **Upgrade interaction** | Global multipliers first, club-specific later | Phase 1 works with zero upgrade changes |
| **Auto-suggestion** | Zone-based priority, then distance-based | Green -> putter, Tee -> driver, otherwise by range |
| **Bag upgrades** | Unlock new clubs as roguelike upgrade rewards | Gives run-over-run bag growth alongside stat upgrades |
