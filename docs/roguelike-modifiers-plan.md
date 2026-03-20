# Roguelike Modifiers — Design & Status

## Context

The game already has a stat-based upgrade system (power, friction, bounce, accuracy, gravity) applied between holes via `UpgradeDefinition` resources. This document covers a broader category: **modifiers** — roguelike abilities and rule-bending effects that go beyond flat stat changes.

Modifiers are picked up through the same between-hole upgrade screen but introduce new mechanics rather than tweaking numbers. They fall into two major categories so far, with room to grow:

| Category | What It Changes | Examples |
|----------|----------------|---------|
| **Terrain Modifiers** | Influence how the next hole's terrain is generated | Flatten hills, widen fairways, raise/lower water |
| **Ball Actions** | Grant activated abilities while the ball is in flight or rolling | Mid-air jump, speed boost, spin correction |

---

## Terrain Modifiers

Modifiers that alter terrain generation parameters for upcoming holes. These give the player agency over the course itself — a core roguelike fantasy of reshaping the world to suit your build.

**Full design details are in [terrain-generation-plan.md](terrain-generation-plan.md#terrain-modifiers-roguelike-integration) (Phase 11).**

### Summary

When a player picks a terrain modifier, it writes overrides into a `TerrainModifierStack` that the terrain generation pipeline reads at generation time. Modifiers are scoped — some last one hole, some last the rest of the run.

Example terrain modifiers:

| Modifier | Effect | Duration |
|----------|--------|----------|
| Landscaper | Reduce terrain amplitude by 30% (flatter hills) | 3 holes |
| Channel Digger | Increase fairway width by 25% | 3 holes |
| Drought | Raise water height threshold by 1m (less water) | Rest of run |
| Flood Warning | Lower water height threshold by 1m (more water) | Next hole only |
| Wind Shield | Halve wind strength | 3 holes |
| Archipelago Map | Force island archetype on next hole | Next hole only |
| Valley Map | Force valley corridor archetype on next hole | Next hole only |

Terrain modifiers integrate with the existing `UpgradeDefinition` system by adding a new effect type (`TERRAIN_OVERRIDE`) to `UpgradeEffect`, so they appear as normal upgrade cards and are picked through the same UI.

---

## Ball Actions

Activated abilities the player can trigger while their ball is in flight or rolling. Unlike passive stat upgrades, these require timing and player skill — press the right button at the right moment for an advantage.

### Design Principles

- **Limited charges per hole** — actions aren't free; each has a charge count that resets per hole (or per shot, depending on the action)
- **Timing matters** — a well-timed jump can clear a bunker; a mistimed one wastes the charge
- **Stackable** — picking the same action again increases charges or potency
- **Visible to opponents** — in multiplayer, other players see action effects (for counterplay awareness and spectacle)

### Input

A dedicated action button (default: spacebar / controller X) triggers the equipped action while the ball is in motion. If the player has multiple actions, they cycle with a secondary input or are mapped to number keys.

### Action Catalog

| Action | Trigger Window | Effect | Charges | Stacking |
|--------|---------------|--------|---------|----------|
| **Ball Jump** | While rolling on ground | Ball hops upward (fixed impulse). Clears small obstacles, bunkers, short water crossings | 1/hole | +1 charge per duplicate |
| **Boost** | While in flight or rolling | Burst of forward velocity in current travel direction | 1/hole | +1 charge per duplicate |
| **Spin Correction** | While in flight | Nudge ball trajectory left or right (small lateral impulse based on aim input at activation) | 2/hole | +1 charge per duplicate |
| **Brake** | While rolling | Sharply decelerates the ball (applies heavy friction burst) | 1/hole | +1 charge per duplicate |
| **Backspin** | While in flight, before landing | Adds reverse spin — ball rolls backward on landing | 1/shot | +1 charge per duplicate |

### Architecture Sketch

```
BallAction (Resource)
├── id: String
├── display_name: String
├── description: String
├── rarity: UpgradeDefinition.Rarity
├── trigger_window: TriggerWindow enum { IN_FLIGHT, ON_GROUND, BOTH }
├── charges_per_hole: int
├── charges_per_shot: int  (-1 = use per-hole charges)
├── impulse: Vector3       # direction hint (actual direction computed at runtime)
├── impulse_strength: float
├── effect_type: ActionEffect enum { IMPULSE, FRICTION_BURST, SPIN }
│
├── can_activate(ball_state) → bool   # checks trigger window + remaining charges
└── activate(ball_state) → void       # applies physics effect
```

**Integration with physics:**
- `GolfBall` holds an `active_actions: Array[BallActionInstance]` (action + remaining charges)
- Each simulation frame, `GolfBall` checks for action input and calls `action.can_activate(state)`
- On activation, the action applies its effect directly to the ball's velocity/position in `PhysicsSimulator`
- Charge is consumed; UI updates to show remaining charges

**Integration with upgrades:**
- Ball actions are offered as upgrade cards (new `UpgradeEffect.stat` value: `ACTION`)
- Picking a new action adds it to the player's action loadout
- Picking a duplicate action increases that action's charge count by 1

### UI

- **Action bar** — small HUD element showing equipped actions with charge pips, visible during ball motion
- **Activation flash** — brief visual effect on the ball when an action fires (color-coded per action type)
- **Charge indicator** — pips deplete as charges are used; grey out when empty

---

## Future Modifier Categories

Space reserved for future categories as the design evolves:

- **Hazard modifiers** — change how hazards behave (already noted in terrain plan: Stone Skipper, Heat Rising)
- **Scoring modifiers** — alter scoring rules (mulligan charges, par bonuses)
- **Club modifiers** — change shot mechanics (curve shots, multi-bounce, explosive landing)
- **Passive auras** — persistent effects (attract ball toward cup at close range, headwind resistance)

---

## Implementation Phases

| Phase | What | Status |
|-------|------|--------|
| **1** | `BallAction` resource + `BallActionInstance` runtime wrapper | Planned |
| **2** | Ball Jump action (simplest — ground trigger, upward impulse) | Planned |
| **3** | Action input handling in `GolfBall` + charge tracking | Planned |
| **4** | Action bar UI + activation VFX | Planned |
| **5** | Boost, Spin Correction, Brake, Backspin actions | Planned |
| **6** | Actions as upgrade cards (integration with `UpgradeRegistry`) | Planned |
| **7** | `TerrainModifierStack` + terrain modifier pipeline integration | Planned |
| **8** | Terrain modifier upgrade cards | Planned |
| **9** | Multiplayer sync for action activations | Planned |
