## HazardDefinition — data resource describing a dynamic hazard type.
##
## Each hazard type (rock slide, sand geyser, lightning, etc.) is a .tres file
## with placement rules, timing, effect parameters, and a reference to the
## GDScript subclass that builds visuals and computes impulse.
##
## Biomes reference these via HazardEntry (definition + density) in their
## hazard_definitions array, so adding a new hazard requires only a new .tres
## and a new subclass — no enums or match statements to update.
class_name HazardDefinition
extends Resource

enum PlacementStrategy {
	ALONG_FAIRWAY,   ## Centered on the fairway spine (rock slides)
	ON_FAIRWAY,      ## On or near the fairway with lateral offset (geysers)
	RANDOM_IN_BOUNDS, ## Anywhere within playable bounds
}

enum CollisionMode {
	AREA,      ## Trigger when ball enters the Area3D (geysers)
	PROXIMITY, ## Trigger when ball is near a moving collider (rock slides)
}

@export var hazard_name: StringName = &""

## The DynamicHazardBase subclass to instantiate at runtime.
@export var hazard_script: GDScript

@export_group("Placement")

@export var placement_strategy: PlacementStrategy = PlacementStrategy.ALONG_FAIRWAY

## Earliest placement along the hole (0 = tee, 1 = cup).
@export_range(0.0, 1.0, 0.05) var min_t: float = 0.2

## Latest placement along the hole.
@export_range(0.0, 1.0, 0.05) var max_t: float = 0.8

## Maximum lateral offset as a fraction of fairway width (ON_FAIRWAY only).
@export_range(0.0, 1.0, 0.05) var lateral_offset: float = 0.0

## Orient the hazard perpendicular to the fairway direction.
@export var perpendicular: bool = false

## Count formula: int(hole_length / count_divisor * density). Lower = more hazards.
@export_range(20.0, 200.0, 5.0) var count_divisor: float = 50.0

@export_range(0, 6) var max_count: int = 3

@export_group("Timing")

## Min/max cycle period in seconds (randomized per instance).
@export var cycle_period_range: Vector2 = Vector2(6.0, 10.0)

## Min/max active duration in seconds.
@export var active_duration_range: Vector2 = Vector2(2.0, 3.0)

@export_range(0.5, 5.0, 0.1) var warning_duration: float = 1.5

@export_group("Effect")

## Base impulse strength applied to the ball.
@export_range(1.0, 30.0, 0.5) var base_intensity: float = 8.0

## Intensity randomization range (±).
@export_range(0.0, 10.0, 0.5) var intensity_variance: float = 3.0

## Flat effect radius in metres. Used when effect_radius_fairway_factor is 0.
@export_range(1.0, 20.0, 0.5) var effect_radius: float = 3.0

## When > 0, effect_radius = fairway_width * this factor (overrides flat radius).
## Rock slides use 0.6; geysers use 0 (flat radius).
@export_range(0.0, 2.0, 0.05) var effect_radius_fairway_factor: float = 0.0

@export var collision_mode: CollisionMode = CollisionMode.AREA

## Radius for PROXIMITY collision checks (distance from collider to ball).
@export_range(0.5, 5.0, 0.1) var proximity_hit_radius: float = 2.0
