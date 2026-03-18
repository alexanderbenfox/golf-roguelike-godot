## HoleGenConfig — exported Resource that controls all procedural hole parameters.
##
## Attach an instance to CourseManager's `config` export in the Inspector,
## or assign one of the static difficulty presets in code:
##
##   course_manager.config = HoleGenConfig.easy()
##   course_manager.config = HoleGenConfig.hard()
##
## Every parameter has a sensible default so the game works without any config set.
class_name HoleGenConfig
extends Resource

## ---- Par --------------------------------------------------------------------

## Minimum par value rolled per hole.
@export_range(3, 5) var min_par: int = 3
## Maximum par value rolled per hole.
@export_range(3, 5) var max_par: int = 5

## ---- Hole length ------------------------------------------------------------

## Multiplier applied to all par-based length ranges.
## 1.0 = default lengths. 0.75 = shorter holes. 1.5 = longer holes.
@export_range(0.5, 2.0, 0.05) var length_multiplier: float = 1.0

## ---- Fairway ----------------------------------------------------------------

## Scales the fairway width range. > 1.0 = wider (easier). < 1.0 = narrower (harder).
@export_range(0.25, 2.0, 0.05) var fairway_width_scale: float = 1.0

## ---- Direction variety ------------------------------------------------------

## How much holes deviate from straight forward.
## 0.0 = all holes go straight. 1.0 = full ±50° variance.
@export_range(0.0, 1.0, 0.05) var direction_variety: float = 1.0

## ---- Biome ------------------------------------------------------------------

## Biome definition for this course. Controls per-zone colors, friction, and
## terrain material. Leave null to use the default Meadow biome.
@export var biome: BiomeDefinition = null

## ---- Obstacles --------------------------------------------------------------

## Multiplier on the number of tree pairs placed along the fairway.
## 0.0 = no trees. 2.0 = twice as many.
@export_range(0.0, 3.0, 0.1) var tree_density: float = 1.0

## Multiplier on the number of bunkers placed near the green (0–2 base).
## Also scales fairway bunker probability.
@export_range(0.0, 3.0, 0.1) var bunker_density: float = 1.0


## ---- Static difficulty presets ----------------------------------------------

static func easy() -> HoleGenConfig:
	var c := HoleGenConfig.new()
	c.min_par = 3
	c.max_par = 4
	c.length_multiplier = 0.75
	c.fairway_width_scale = 1.5
	c.direction_variety = 0.4
	c.tree_density = 0.5
	c.bunker_density = 0.25
	return c


static func medium() -> HoleGenConfig:
	return HoleGenConfig.new()  # all defaults


static func hard() -> HoleGenConfig:
	var c := HoleGenConfig.new()
	c.min_par = 4
	c.max_par = 5
	c.length_multiplier = 1.3
	c.fairway_width_scale = 0.65
	c.direction_variety = 1.0
	c.tree_density = 1.8
	c.bunker_density = 2.0
	return c
