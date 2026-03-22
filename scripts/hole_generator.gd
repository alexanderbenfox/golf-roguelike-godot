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
const PolylineUtilsScript = preload("res://scripts/utility/polyline_utils.gd")


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
	var fairway_spine: Array[Vector3]  # polyline from tee to cup (may have dogleg waypoints)
	var obstacles: Array[ObstacleDescriptor]
	var dynamic_hazards: Array[DynamicHazardDescriptor]
	var terrain_data: RefCounted  # TerrainData — heightmap + zones for this hole
	var wind: Vector3  # horizontal wind vector for this hole

	func _init() -> void:
		tee_position = Vector3.ZERO
		fairway_spine = []
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

	# Length scales with par, then multiplied by config + size_scale
	var base_length: float
	match par:
		3: base_length = rng.randf_range(100.0, 180.0)
		4: base_length = rng.randf_range(220.0, 380.0)
		5: base_length = rng.randf_range(360.0, 560.0)
		_: base_length = rng.randf_range(120.0, 200.0)
	layout.hole_length = base_length * cfg.length_multiplier * cfg.size_scale

	# Fairway width scales with par, config, and size_scale
	var base_width: float
	match par:
		3: base_width = rng.randf_range(14.0, 22.0)
		4: base_width = rng.randf_range(20.0, 30.0)
		5: base_width = rng.randf_range(26.0, 38.0)
		_: base_width = rng.randf_range(16.0, 24.0)
	layout.fairway_width = base_width * cfg.fairway_width_scale * cfg.size_scale

	# Resolve biome early so spine can use archetype info
	var resolved_biome: BiomeDefinition = biome
	if not resolved_biome and cfg.biome:
		resolved_biome = cfg.biome
	if not resolved_biome:
		resolved_biome = BiomeDefinitionScript.create_meadow()

	# Generate fairway spine — may include dogleg waypoints for par 4-5
	# Uses sub-RNG so the draw count is deterministic regardless of dogleg chance
	var spine_seed: int = rng.randi()
	var archetype: int = resolved_biome.terrain_archetype

	# Resolve curve params: biome override (>= 0) wins, else config
	var rb: BiomeDefinition = resolved_biome
	var r_min_bends: int = rb.curve_min_bends \
		if rb.curve_min_bends >= 0 else cfg.min_bends
	var r_max_bends: int = rb.curve_max_bends \
		if rb.curve_max_bends >= 0 else cfg.max_bends
	var r_tightness: float = rb.curve_tightness \
		if rb.curve_tightness >= 0.0 else cfg.curve_tightness
	var r_s_bias: float = rb.curve_s_bias \
		if rb.curve_s_bias >= 0.0 else cfg.s_curve_bias
	var r_smoothing: int = rb.curve_smoothing \
		if rb.curve_smoothing >= 0 else cfg.curve_smoothing
	var r_spread: float = rb.curve_spread \
		if rb.curve_spread >= 0.0 else cfg.curve_spread

	layout.fairway_spine = _generate_spine(
		spine_seed, layout.tee_position, layout.hole_direction,
		layout.hole_length, par, archetype,
		r_min_bends, r_max_bends, r_tightness,
		r_s_bias, r_smoothing, r_spread,
	)
	layout.cup_position = layout.fairway_spine[layout.fairway_spine.size() - 1]
	layout.cup_position.y = 0.4

	_generate_obstacles(rng, layout, cfg)

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
		layout.fairway_spine,
		layout.fairway_width,
		0.5,   # ground_height
		cell_size,
		terrain_margin,
		resolved_biome,
		bunkers,
	)

	return layout


# -------------------------------------------------------------------------
# Spine generation (dogleg routing)
# -------------------------------------------------------------------------

## Build a fairway spine from tee to cup. Par 4-5 may get dogleg waypoints.
## Uses a dedicated sub-RNG so the draw count is deterministic regardless
## of whether a dogleg is generated.
static func _generate_spine(
	rng_seed: int,
	tee_pos: Vector3,
	hole_direction: float,
	hole_length: float,
	par: int,
	archetype: int = 0,
	p_min_bends: int = 0,
	p_max_bends: int = 0,
	p_curve_tightness: float = 0.5,
	p_s_curve_bias: float = 0.0,
	p_curve_smoothing: int = 0,
	p_curve_spread: float = 0.0,
) -> Array[Vector3]:
	var spine_rng := RandomNumberGenerator.new()
	spine_rng.seed = rng_seed

	# DONUT_LAKE (3): hook-shaped spine — tee on outside, cup in center
	if archetype == 3:
		return _generate_donut_spine(
			spine_rng, tee_pos, hole_direction, hole_length,
		)

	var dir := Vector3(
		sin(hole_direction), 0.0, -cos(hole_direction),
	)

	# Determine number of bends
	var num_turns: int = 0
	if p_max_bends > 0:
		# Explicit override from config
		num_turns = spine_rng.randi_range(p_min_bends, p_max_bends)
	else:
		# Par-based defaults
		if par == 3 and spine_rng.randf() < 0.3:
			num_turns = 1
		elif par == 4:
			num_turns = 1
			if spine_rng.randf() < 0.5:
				num_turns = 2
		elif par >= 5:
			num_turns = 2
			if spine_rng.randf() < 0.5:
				num_turns = 3

	if num_turns == 0:
		# Straight hole
		var cup := tee_pos + dir * hole_length
		return [tee_pos, cup] as Array[Vector3]

	# ---- Zigzag path for significant spread ------------------------------------
	# The turn-based approach (below) accumulates heading changes that always
	# push perpendicular displacement in the SAME direction (staircase, not
	# S-curve). For real serpentine shapes, place waypoints directly as a
	# zigzag that alternates left/right of the tee-to-cup centerline.
	if p_curve_spread > 0.1 and num_turns >= 2:
		var fwd := Vector3(
			sin(hole_direction), 0.0, -cos(hole_direction),
		)
		var perp := Vector3(-fwd.z, 0.0, fwd.x)

		# Sweep amplitude — how far corners extend to each side.
		# At spread 1.0 on a 300-unit hole → 150 units per side.
		var amplitude: float = hole_length * p_curve_spread * 0.5

		var spine: Array[Vector3] = [tee_pos]
		var side: float = 1.0 if spine_rng.randf() > 0.5 else -1.0

		for i: int in range(num_turns):
			# Evenly distribute corners along the forward axis
			var t: float = float(i + 1) / float(num_turns + 1)
			t += spine_rng.randf_range(-0.03, 0.03)
			t = clampf(t, 0.05, 0.95)

			var amp: float = amplitude * spine_rng.randf_range(
				0.75, 1.0,
			)
			var wp: Vector3 = tee_pos \
				+ fwd * (hole_length * t) \
				+ perp * side * amp
			spine.append(wp)

			# Alternate sides — s_curve_bias controls reliability
			if spine_rng.randf() < p_s_curve_bias:
				side = -side
			else:
				side = -side if spine_rng.randf() > 0.5 else side

		spine.append(tee_pos + fwd * hole_length)

		# Aggressive smoothing turns the zigzag into flowing S-curves.
		# High pullback (0.45) makes wide arcs; extra subdivisions keep
		# them round instead of segmented.
		var zigzag_subdivs: int = maxi(p_curve_smoothing * 2, 8)
		if spine.size() > 2:
			spine = _smooth_spine(spine, zigzag_subdivs, 0.45)
		return spine

	# ---- Turn-based path for low/no spread ----------------------------------
	# Turn angle range derived from curve_tightness
	# 0.0 → gentle 5–20°   0.5 → default 30–75°   1.0 → tight 60–120°
	var min_angle: float = lerpf(PI / 36.0, PI / 3.0, p_curve_tightness)
	var max_angle: float = lerpf(PI / 9.0, PI * 2.0 / 3.0, p_curve_tightness)

	# Pre-compute all segment lengths (including final) from total length
	var num_segs: int = num_turns + 1
	var raw_lengths: Array[float] = []
	var raw_total: float = 0.0
	for i: int in range(num_segs):
		var frac: float
		if num_turns == 1:
			if i == 0:
				frac = spine_rng.randf_range(0.35, 0.65)
			else:
				frac = 1.0  # placeholder, gets normalised
		else:
			frac = spine_rng.randf_range(0.7, 1.3)
		raw_lengths.append(frac)
		raw_total += frac
	# Normalise so they sum to hole_length
	for i: int in range(num_segs):
		raw_lengths[i] = raw_lengths[i] / raw_total * hole_length

	# Build waypoints along a turning path
	var spine: Array[Vector3] = [tee_pos]
	var current_pos: Vector3 = tee_pos
	var current_angle: float = hole_direction
	var last_turn_sign: float = 0.0

	for i: int in range(num_turns):
		var segment_length: float = raw_lengths[i]

		var seg_dir := Vector3(
			sin(current_angle), 0.0, -cos(current_angle),
		)
		var waypoint: Vector3 = current_pos + seg_dir * segment_length
		spine.append(waypoint)
		current_pos = waypoint

		# Determine turn direction — s_curve_bias controls alternation
		var turn_sign: float
		if last_turn_sign != 0.0 and spine_rng.randf() < p_s_curve_bias:
			turn_sign = -last_turn_sign
		else:
			turn_sign = 1.0 if spine_rng.randf() > 0.5 else -1.0
		last_turn_sign = turn_sign

		var turn_amount: float = spine_rng.randf_range(
			min_angle, max_angle,
		) * turn_sign
		current_angle += turn_amount

	# Final segment to the cup
	var final_dir := Vector3(
		sin(current_angle), 0.0, -cos(current_angle),
	)
	spine.append(current_pos + final_dir * raw_lengths[num_turns])

	# Smooth sharp doglegs into arcs
	if p_curve_smoothing > 0 and spine.size() > 2:
		spine = _smooth_spine(spine, p_curve_smoothing, 0.35)

	return spine


## Smooth internal corners of a spine using quadratic bezier arcs.
## Each internal waypoint is replaced by arc points for a natural curve.
static func _smooth_spine(
	spine: Array[Vector3],
	points_per_bend: int,
	pullback_fraction: float = 0.35,
) -> Array[Vector3]:
	var result: Array[Vector3] = [spine[0]]

	for i: int in range(1, spine.size() - 1):
		var prev: Vector3 = spine[i - 1]
		var curr: Vector3 = spine[i]
		var next_pt: Vector3 = spine[i + 1]

		# Pull-back: fraction of the shorter adjacent segment
		var len_prev: float = (curr - prev).length()
		var len_next: float = (next_pt - curr).length()
		var pullback: float = minf(len_prev, len_next) \
			* pullback_fraction

		# Quadratic bezier: P0 on incoming, P1 at corner, P2 on outgoing
		var dir_in: Vector3 = (curr - prev).normalized()
		var dir_out: Vector3 = (next_pt - curr).normalized()
		var p0: Vector3 = curr - dir_in * pullback
		var p1: Vector3 = curr
		var p2: Vector3 = curr + dir_out * pullback

		for j: int in range(points_per_bend + 1):
			var t: float = float(j) / float(points_per_bend)
			var a: Vector3 = p0.lerp(p1, t)
			var b: Vector3 = p1.lerp(p2, t)
			result.append(a.lerp(b, t))

	result.append(spine[spine.size() - 1])
	return result


## Donut spine: tee on the outside of a ring, fairway curves around in a
## semi-circle, then hooks inward to the cup near the center.
## This creates a C/hook shape where the player wraps around a central lake.
static func _generate_donut_spine(
	rng: RandomNumberGenerator,
	tee_pos: Vector3,
	hole_direction: float,
	hole_length: float,
) -> Array[Vector3]:
	# Ring radius — roughly hole_length / PI so the arc is about hole_length
	var ring_radius: float = hole_length / PI * rng.randf_range(0.9, 1.1)

	# Center of the ring — offset from tee by ring_radius along hole direction
	var dir := Vector3(
		sin(hole_direction), 0.0, -cos(hole_direction),
	)
	var ring_center: Vector3 = tee_pos + dir * ring_radius

	# Which side to curve around (left or right)
	var curve_sign: float = 1.0 if rng.randf() > 0.5 else -1.0

	# Build arc waypoints from tee around the ring toward center
	# Tee is at angle 0 (relative to ring center), arc sweeps ~180 degrees
	var tee_offset: Vector3 = tee_pos - ring_center
	var start_angle: float = atan2(tee_offset.x, -tee_offset.z)

	var arc_segments: int = 5
	var total_arc: float = PI * rng.randf_range(0.75, 0.9) * curve_sign

	var spine: Array[Vector3] = [tee_pos]
	for i: int in range(1, arc_segments):
		var t: float = float(i) / float(arc_segments)
		var angle: float = start_angle + total_arc * t
		var pt := Vector3(
			ring_center.x + sin(angle) * ring_radius,
			0.0,
			ring_center.z - cos(angle) * ring_radius,
		)
		spine.append(pt)

	# Final hook inward: last arc point → ring center (the cup)
	# Add an intermediate point partway in for a smooth curve
	var last_arc: Vector3 = spine[spine.size() - 1]
	var to_center: Vector3 = ring_center - last_arc
	var mid_hook: Vector3 = last_arc + to_center * 0.5
	spine.append(mid_hook)
	spine.append(ring_center)

	return spine


# -------------------------------------------------------------------------
# Obstacle generation
# -------------------------------------------------------------------------

static func _generate_obstacles(rng: RandomNumberGenerator, layout: HoleLayout, cfg: HoleGenConfig) -> void:
	var spine: Array[Vector3] = layout.fairway_spine

	# --- Trees along fairway sides ---
	# Base: one pair every 25 units, scaled by tree_density.
	var num_pairs := maxi(0, int(layout.hole_length / 25.0 * cfg.tree_density))
	for i in range(num_pairs):
		var t := (float(i) + 0.5 + rng.randf_range(-0.2, 0.2)) / float(num_pairs)
		t = clampf(t * 0.85 + 0.05, 0.05, 0.90)  # keep away from tee/cup
		var along: Vector3 = PolylineUtilsScript.sample_position(spine, t)
		var local_dir: Vector3 = PolylineUtilsScript.sample_direction(spine, t)
		var local_right: Vector3 = PolylineUtilsScript.direction_to_right(local_dir)
		var side_offset := layout.fairway_width * 0.5 + rng.randf_range(1.0, 5.0)

		# Left tree (always)
		var lt := ObstacleDescriptor.new()
		lt.type = ObstacleDescriptor.Type.TREE
		lt.world_position = along + local_right * -side_offset
		lt.radius = rng.randf_range(0.6, 1.2)
		lt.height = rng.randf_range(4.0, 8.0)
		layout.obstacles.append(lt)

		# Right tree (75% chance)
		if rng.randf() > 0.25:
			var rt := ObstacleDescriptor.new()
			rt.type = ObstacleDescriptor.Type.TREE
			rt.world_position = along + local_right * (side_offset + rng.randf_range(-2.0, 2.0))
			rt.radius = rng.randf_range(0.6, 1.2)
			rt.height = rng.randf_range(4.0, 8.0)
			layout.obstacles.append(rt)

	# --- Trees scattered between S-curve legs ---
	var resolved_biome: BiomeDefinition = cfg.biome
	var ic_density: float = resolved_biome.inter_curve_density \
		if resolved_biome else 0.0
	if ic_density > 0.0 and spine.size() >= 4:
		var detect_range: float = layout.fairway_width * 4.0
		var half_fw: float = layout.fairway_width * 0.5
		var placed: int = 0
		var target: int = int(10.0 * ic_density * cfg.tree_density)
		for _t_idx: int in range(target * 4):  # oversample, reject bad
			if placed >= target:
				break
			# Random position near a spine point
			var sample_t: float = rng.randf_range(0.1, 0.9)
			var center: Vector3 = \
				PolylineUtilsScript.sample_position(
					spine, sample_t,
				)
			var candidate := Vector3(
				center.x + rng.randf_range(
					-detect_range, detect_range,
				),
				0.0,
				center.z + rng.randf_range(
					-detect_range, detect_range,
				),
			)
			# Must be far enough from fairway
			var dt: Array[float] = \
				PolylineUtilsScript.min_distance_and_t_xz(
					candidate, spine,
				)
			if dt[0] < half_fw * 1.5:
				continue
			# Must be between curve legs: check if a point at a
			# very different parametric t is also close
			var found_far_t: bool = false
			for check_t: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				if absf(check_t - dt[1]) < 0.25:
					continue
				var check_pos: Vector3 = \
					PolylineUtilsScript.sample_position(
						spine, check_t,
					)
				var check_flat := Vector3(
					check_pos.x, 0.0, check_pos.z,
				)
				var cand_flat := Vector3(
					candidate.x, 0.0, candidate.z,
				)
				if check_flat.distance_to(cand_flat) < detect_range:
					found_far_t = true
					break
			if not found_far_t:
				continue
			var tree := ObstacleDescriptor.new()
			tree.type = ObstacleDescriptor.Type.TREE
			tree.world_position = candidate
			tree.radius = rng.randf_range(0.8, 1.5)
			tree.height = rng.randf_range(5.0, 10.0)
			layout.obstacles.append(tree)
			placed += 1

	# --- Bunkers near the green (0–2, scaled by bunker_density) ---
	var num_green_bunkers := int(rng.randi_range(0, 2) * cfg.bunker_density)
	for i in range(num_green_bunkers):
		var b := ObstacleDescriptor.new()
		b.type = ObstacleDescriptor.Type.BUNKER
		# Place near the cup end of the spine (t = 0.85–0.95)
		var green_t: float = rng.randf_range(0.85, 0.95)
		var green_pos: Vector3 = PolylineUtilsScript.sample_position(spine, green_t)
		var green_dir: Vector3 = PolylineUtilsScript.sample_direction(spine, green_t)
		var green_right: Vector3 = PolylineUtilsScript.direction_to_right(green_dir)
		var side := green_right * rng.randf_range(
			-layout.fairway_width * 0.8,
			layout.fairway_width * 0.8,
		)
		b.world_position = green_pos + side
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
		var fw_pos: Vector3 = PolylineUtilsScript.sample_position(spine, t)
		var fw_dir: Vector3 = PolylineUtilsScript.sample_direction(spine, t)
		var fw_right: Vector3 = PolylineUtilsScript.direction_to_right(fw_dir)
		var side_sign := 1.0 if rng.randf() > 0.5 else -1.0
		b.world_position = fw_pos \
			+ fw_right * side_sign * (
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
	for entry: Resource in biome.hazard_definitions:
		_place_hazards_from_definition(
			rng, layout, entry,
		)


## Generic placement driven by a HazardEntry (definition + density).
static func _place_hazards_from_definition(
	rng: RandomNumberGenerator,
	layout: HoleLayout,
	entry: Resource,  # HazardEntry
) -> void:
	var def: Resource = entry.definition  # HazardDefinition
	if not def:
		return
	var density: float = entry.density
	var spine: Array[Vector3] = layout.fairway_spine

	var count := clampi(
		int(layout.hole_length / def.count_divisor * density),
		0, def.max_count,
	)
	for i: int in range(count):
		var h := DynamicHazardDescriptor.new()
		h.hazard_definition = def

		# Position along spine
		var t := rng.randf_range(def.min_t, def.max_t)
		var pos: Vector3 = PolylineUtilsScript.sample_position(spine, t)
		var local_dir: Vector3 = PolylineUtilsScript.sample_direction(spine, t)
		var local_right: Vector3 = PolylineUtilsScript.direction_to_right(local_dir)

		# Lateral offset based on placement strategy
		# PlacementStrategy: ALONG_FAIRWAY=0, ON_FAIRWAY=1, RANDOM=2
		if def.placement_strategy == 1:  # ON_FAIRWAY
			var lat_range: float = def.lateral_offset \
				* layout.fairway_width
			pos += local_right * rng.randf_range(-lat_range, lat_range)
		elif def.placement_strategy == 2:  # RANDOM_IN_BOUNDS
			var lat: float = layout.fairway_width * 1.5
			pos += local_right * rng.randf_range(-lat, lat)

		pos.y = 0.5  # adjusted to terrain height at build time
		h.world_position = pos

		# Direction
		if def.perpendicular:
			var side_sign: float = 1.0 if rng.randf() > 0.5 \
				else -1.0
			h.direction = local_right * side_sign
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
