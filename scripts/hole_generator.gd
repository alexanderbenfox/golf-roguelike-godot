## HoleGenerator — pure data class, no Godot nodes.
## Given an RNG state + par, produces a HoleLayout describing:
##   - Tee and cup positions (cup is relative to tee at world origin)
##   - Hole direction and length (par-scaled)
##   - Obstacle list (trees + bunkers)
##
## Always call generate() with the shared course RNG so holes are
## deterministic from the course seed regardless of platform.
class_name HoleGenerator
extends RefCounted

const HoleGenConfigScript = preload("res://scripts/hole_gen_config.gd")
const HeightmapGeneratorScript = preload("res://scripts/terrain/heightmap_generator.gd")
const TerrainDataScript = preload("res://scripts/terrain/terrain_data.gd")
const BiomeDefinitionScript = preload("res://resources/biome_definition.gd")


# -------------------------------------------------------------------------
# Data types
# -------------------------------------------------------------------------

class ObstacleDescriptor:
	enum Type { TREE, BUNKER }
	var type: Type
	var world_position: Vector3
	var radius: float
	var height: float      # trees only
	var aspect_ratio: float = 1.0  # bunkers: elongation (>1 = longer along rotation axis)
	var rotation: float = 0.0     # bunkers: radians, orientation of the long axis


class DynamicHazardDescriptor:
	var hazard_definition: Resource   # HazardDefinition — drives instantiation + collision mode
	var world_position: Vector3      # center of the hazard zone
	var direction: Vector3           # slide direction (rocks) or ejection hint (geysers)
	var effect_radius: float         # radius of ball interaction area
	var cycle_period: float          # seconds for one full cycle
	var active_duration: float       # seconds the hazard is dangerous per cycle
	var warning_duration: float      # seconds of visual warning before activation
	var phase_offset: float          # offset into cycle for staggering
	var intensity: float             # impulse strength


class HoleLayout:
	var hole_number: int
	var par: int
	var tee_position: Vector3   # always Vector3.ZERO — scene root is the tee
	var cup_position: Vector3   # world-space offset from tee
	var hole_direction: float   # radians, measured from -Z (forward)
	var hole_length: float
	var fairway_width: float
	var obstacles: Array[ObstacleDescriptor]
	var dynamic_hazards: Array[DynamicHazardDescriptor]
	var terrain_data: RefCounted  # TerrainData — heightmap + zones for this hole
	var wind: Vector3  # horizontal wind vector for this hole

	func _init() -> void:
		tee_position = Vector3.ZERO
		obstacles = []
		dynamic_hazards = []
		wind = Vector3.ZERO


# -------------------------------------------------------------------------
# Entry point
# -------------------------------------------------------------------------

## Generate a HoleLayout by consuming from the shared RNG.
## Caller must advance rng state consistently (call once per hole, in order).
## Pass a HoleGenConfig to override generation parameters; null uses defaults.
## An explicit biome overrides config.biome (used by CourseManager's
## biome_sequence to assign per-hole biomes).
static func generate(
	rng: RandomNumberGenerator,
	hole_number: int,
	par: int,
	config: HoleGenConfig = null,
	biome: BiomeDefinition = null,
	cell_size: float = 2.0,
	terrain_margin: float = 30.0,
) -> HoleLayout:
	var cfg: HoleGenConfig = \
		config if config != null else HoleGenConfigScript.new()

	var layout := HoleLayout.new()
	layout.hole_number = hole_number
	layout.par = par

	# Direction: scaled by direction_variety (0 = straight, 1 = ±50°)
	var max_angle: float = (PI / 3.6) * cfg.direction_variety
	layout.hole_direction = rng.randf_range(-max_angle, max_angle)

	# Length scales with par, then multiplied by config
	var base_length: float
	match par:
		3: base_length = rng.randf_range(60.0, 100.0)
		4: base_length = rng.randf_range(120.0, 160.0)
		5: base_length = rng.randf_range(180.0, 240.0)
		_: base_length = rng.randf_range(80.0, 120.0)
	layout.hole_length = base_length * cfg.length_multiplier

	# Cup position from tee
	var dir := Vector3(
		sin(layout.hole_direction), 0.0,
		-cos(layout.hole_direction),
	)
	layout.cup_position = dir * layout.hole_length
	layout.cup_position.y = 0.4

	# Fairway width scales with par and config
	var base_width: float
	match par:
		3: base_width = rng.randf_range(10.0, 16.0)
		4: base_width = rng.randf_range(14.0, 22.0)
		5: base_width = rng.randf_range(18.0, 28.0)
		_: base_width = rng.randf_range(12.0, 20.0)
	layout.fairway_width = base_width * cfg.fairway_width_scale

	_generate_obstacles(rng, layout, cfg)

	# Resolve biome: explicit param > config > meadow default
	var resolved_biome: BiomeDefinition = biome
	if not resolved_biome and cfg.biome:
		resolved_biome = cfg.biome
	if not resolved_biome:
		resolved_biome = BiomeDefinitionScript.create_meadow()

	# Generate per-hole wind from biome params + RNG
	if resolved_biome and resolved_biome.base_wind_strength > 0.0:
		var wind_angle: float = rng.randf() * TAU
		var wind_strength: float = maxf(0.0,
			resolved_biome.base_wind_strength + rng.randf_range(
				-resolved_biome.wind_variance,
				resolved_biome.wind_variance,
			))
		layout.wind = Vector3(
			cos(wind_angle), 0.0, sin(wind_angle),
		) * wind_strength

	# Generate dynamic hazards (sub-RNG so parent draw count is fixed)
	var hazard_rng_seed: int = rng.randi()
	if resolved_biome and resolved_biome.hazard_definitions.size() > 0:
		var hazard_rng := RandomNumberGenerator.new()
		hazard_rng.seed = hazard_rng_seed
		_generate_dynamic_hazards(
			hazard_rng, layout, resolved_biome,
		)

	# Extract bunker positions for terrain painting
	var bunkers: Array = []
	for obs in layout.obstacles:
		if obs.type == ObstacleDescriptor.Type.BUNKER:
			bunkers.append(obs)

	# Generate terrain heightmap + zones (biome set on terrain inside)
	layout.terrain_data = HeightmapGeneratorScript.generate(
		rng,
		layout.tee_position,
		layout.cup_position,
		layout.hole_direction,
		layout.hole_length,
		layout.fairway_width,
		0.5,   # ground_height
		cell_size,
		terrain_margin,
		resolved_biome,
		bunkers,
	)

	return layout


# -------------------------------------------------------------------------
# Obstacle generation
# -------------------------------------------------------------------------

static func _generate_obstacles(rng: RandomNumberGenerator, layout: HoleLayout, cfg: HoleGenConfig) -> void:
	var dir   := Vector3(sin(layout.hole_direction), 0.0, -cos(layout.hole_direction))
	var right := Vector3(cos(layout.hole_direction), 0.0,  sin(layout.hole_direction))

	# --- Trees along fairway sides ---
	# Base: one pair every 25 units, scaled by tree_density.
	var num_pairs := maxi(0, int(layout.hole_length / 25.0 * cfg.tree_density))
	for i in range(num_pairs):
		var t := (float(i) + 0.5 + rng.randf_range(-0.2, 0.2)) / float(num_pairs)
		var along := dir * (t * layout.hole_length * 0.85)
		var side_offset := layout.fairway_width * 0.5 + rng.randf_range(1.0, 5.0)

		# Left tree (always)
		var lt := ObstacleDescriptor.new()
		lt.type = ObstacleDescriptor.Type.TREE
		lt.world_position = along + right * -side_offset
		lt.radius = rng.randf_range(0.6, 1.2)
		lt.height = rng.randf_range(4.0, 8.0)
		layout.obstacles.append(lt)

		# Right tree (75% chance)
		if rng.randf() > 0.25:
			var rt := ObstacleDescriptor.new()
			rt.type = ObstacleDescriptor.Type.TREE
			rt.world_position = along + right * (side_offset + rng.randf_range(-2.0, 2.0))
			rt.radius = rng.randf_range(0.6, 1.2)
			rt.height = rng.randf_range(4.0, 8.0)
			layout.obstacles.append(rt)

	# --- Bunkers near the green (0–2, scaled by bunker_density) ---
	var num_green_bunkers := int(rng.randi_range(0, 2) * cfg.bunker_density)
	for i in range(num_green_bunkers):
		var b := ObstacleDescriptor.new()
		b.type = ObstacleDescriptor.Type.BUNKER
		var back := dir * (layout.hole_length - rng.randf_range(5.0, 14.0))
		var side := right * rng.randf_range(
			-layout.fairway_width * 0.8,
			layout.fairway_width * 0.8,
		)
		b.world_position = back + side
		b.world_position.y = 0.0
		b.radius = rng.randf_range(4.0, 7.0)
		b.aspect_ratio = rng.randf_range(1.0, 2.2)
		b.rotation = rng.randf_range(0.0, TAU)
		layout.obstacles.append(b)

	# --- Fairway bunker (chance scales with bunker_density, par 4+) ---
	var fairway_bunker_threshold: float = 0.5 / maxf(cfg.bunker_density, 0.01)
	if layout.par >= 4 and rng.randf() > fairway_bunker_threshold:
		var b := ObstacleDescriptor.new()
		b.type = ObstacleDescriptor.Type.BUNKER
		var t := rng.randf_range(0.3, 0.6)
		var side_sign := 1.0 if rng.randf() > 0.5 else -1.0
		b.world_position = dir * (t * layout.hole_length) \
			+ right * side_sign * (
				layout.fairway_width * 0.3
				+ rng.randf_range(0.0, 4.0)
			)
		b.world_position.y = 0.0
		b.radius = rng.randf_range(4.0, 6.0)
		b.aspect_ratio = rng.randf_range(1.0, 2.5)
		b.rotation = rng.randf_range(0.0, TAU)
		layout.obstacles.append(b)


# -------------------------------------------------------------------------
# Dynamic hazard generation
# -------------------------------------------------------------------------

## Place dynamic hazards along the fairway from biome's hazard_definitions.
## Uses its own RNG (derived from the parent) so draw count is isolated.
static func _generate_dynamic_hazards(
	rng: RandomNumberGenerator,
	layout: HoleLayout,
	biome: BiomeDefinition,
) -> void:
	var dir := Vector3(
		sin(layout.hole_direction), 0.0,
		-cos(layout.hole_direction),
	)
	var right := Vector3(
		cos(layout.hole_direction), 0.0,
		sin(layout.hole_direction),
	)
	var min_dist_from_tee: float = 15.0
	var min_dist_from_cup: float = 20.0

	for entry: Resource in biome.hazard_definitions:
		_place_hazards_from_definition(
			rng, layout, dir, right, entry,
			min_dist_from_tee, min_dist_from_cup,
		)


## Generic placement driven by a HazardEntry (definition + density).
static func _place_hazards_from_definition(
	rng: RandomNumberGenerator,
	layout: HoleLayout,
	dir: Vector3,
	right: Vector3,
	entry: Resource,  # HazardEntry
	min_from_tee: float,
	min_from_cup: float,
) -> void:
	var def: Resource = entry.definition  # HazardDefinition
	if not def:
		return
	var density: float = entry.density

	var count := clampi(
		int(layout.hole_length / def.count_divisor * density),
		0, def.max_count,
	)
	for i: int in range(count):
		var h := DynamicHazardDescriptor.new()
		h.hazard_definition = def

		# Position along hole
		var t := rng.randf_range(def.min_t, def.max_t)
		var along_dist: float = t * layout.hole_length
		along_dist = clampf(
			along_dist, min_from_tee,
			layout.hole_length - min_from_cup,
		)
		var pos: Vector3 = dir * along_dist

		# Lateral offset based on placement strategy
		# PlacementStrategy: ALONG_FAIRWAY=0, ON_FAIRWAY=1, RANDOM=2
		if def.placement_strategy == 1:  # ON_FAIRWAY
			var lat_range: float = def.lateral_offset \
				* layout.fairway_width
			pos += right * rng.randf_range(-lat_range, lat_range)
		elif def.placement_strategy == 2:  # RANDOM_IN_BOUNDS
			var lat: float = layout.fairway_width * 1.5
			pos += right * rng.randf_range(-lat, lat)

		pos.y = 0.5  # adjusted to terrain height at build time
		h.world_position = pos

		# Direction
		if def.perpendicular:
			var side_sign: float = 1.0 if rng.randf() > 0.5 \
				else -1.0
			h.direction = right * side_sign
		else:
			h.direction = Vector3.UP

		# Effect radius: fairway-relative or flat
		if def.effect_radius_fairway_factor > 0.0:
			h.effect_radius = layout.fairway_width \
				* def.effect_radius_fairway_factor
		else:
			h.effect_radius = def.effect_radius

		# Timing
		h.cycle_period = rng.randf_range(
			def.cycle_period_range.x,
			def.cycle_period_range.y,
		)
		h.active_duration = rng.randf_range(
			def.active_duration_range.x,
			def.active_duration_range.y,
		)
		h.warning_duration = def.warning_duration
		h.phase_offset = rng.randf_range(0.0, h.cycle_period)
		h.intensity = def.base_intensity \
			+ rng.randf_range(
				-def.intensity_variance,
				def.intensity_variance,
			)

		layout.dynamic_hazards.append(h)
