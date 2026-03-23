## HeightmapGenerator — produces a TerrainData from hole routing + noise.
##
## Pure static functions, no Godot nodes. All generation is deterministic
## from the provided RandomNumberGenerator.
##
## Pipeline:
##   1. Paint zones (spatial rules — no height dependency)
##   2. Fill noise (using biome's noise params)
##   3. Apply per-zone height modifiers (hill/valley scale, shape, offset)
##   4. Carve fairway corridor (smooth toward spine elevation)
##   5. Flatten green and tee areas
##   6. Paint bunkers (zone + smooth bowl depression)
##   7. Clamp heights to biome min/max
class_name HeightmapGenerator
extends RefCounted

const TerrainDataScript = preload("res://scripts/terrain/terrain_data.gd")
const BiomeDefinitionScript = preload("res://resources/biome_definition.gd")
const PolylineUtilsScript = preload("res://scripts/utility/polyline_utils.gd")

# Fallback constants when no biome is set
const _DEFAULT_FREQUENCY: float    = 0.012
const _DEFAULT_OCTAVES: int        = 3
const _DEFAULT_LACUNARITY: float   = 2.0
const _DEFAULT_GAIN: float         = 0.5
const _DEFAULT_AMPLITUDE: float    = 3.0
const _DEFAULT_FW_FLATTEN: float   = 0.85
const _DEFAULT_GREEN_RADIUS: float = 10.0
const _DEFAULT_TEE_RADIUS: float   = 5.0
const _DEFAULT_MIN_HEIGHT: float   = -2.0
const _DEFAULT_MAX_HEIGHT: float   = 8.0


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

## Generate a TerrainData for the given hole routing.
## spine: Array[Vector3] polyline from tee to cup (may have dogleg waypoints).
## Pass a BiomeDefinition to use its noise/elevation/zone params;
## null falls back to hardcoded defaults.
## bunkers: Array of ObstacleDescriptors (type=BUNKER) — painted into
## terrain as BUNKER zones with smooth bowl depressions.
static func generate(
	rng: RandomNumberGenerator,
	tee_pos: Vector3,
	cup_pos: Vector3,
	spine_in: Array[Vector3],
	fairway_width: float,
	ground_height: float = 0.5,
	cell_size: float = 2.0,
	margin: float = 30.0,
	biome: BiomeDefinition = null,
	bunkers: Array = [],
) -> RefCounted:
	var noise_seed: int = rng.randi()

	var terrain: RefCounted = TerrainDataScript.new()
	terrain.cell_size = cell_size

	# Build spine with ground_height Y values
	var spine: Array[Vector3] = []
	for pt: Vector3 in spine_in:
		spine.append(Vector3(pt.x, ground_height, pt.z))
	terrain.fairway_spine = spine

	# Compute grid bounds — AABB around all spine points + perpendicular margin
	var fw_var: float = biome.fairway_width_variation \
		if biome else 0.0
	var half_fw: float = fairway_width * (
		0.5 * (1.0 + fw_var * 0.5)
	) + margin
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	# Expand bounds at each spine point with perpendicular + forward margin
	for i: int in range(spine.size()):
		var pt: Vector3 = spine[i]
		# Simple expansion — point ± half_fw in both axes
		min_x = minf(min_x, pt.x - half_fw)
		max_x = maxf(max_x, pt.x + half_fw)
		min_z = minf(min_z, pt.z - half_fw)
		max_z = maxf(max_z, pt.z + half_fw)

	# Also expand along segment perpendiculars for angled segments
	for i: int in range(spine.size() - 1):
		var seg_dir := (spine[i + 1] - spine[i]).normalized()
		var seg_right := Vector3(seg_dir.z, 0.0, -seg_dir.x)
		for endpoint: Vector3 in [spine[i], spine[i + 1]]:
			for side: float in [-1.0, 1.0]:
				var corner: Vector3 = endpoint + seg_right * side * half_fw
				min_x = minf(min_x, corner.x)
				max_x = maxf(max_x, corner.x)
				min_z = minf(min_z, corner.z)
				max_z = maxf(max_z, corner.z)

	terrain.origin = Vector3(min_x, 0.0, min_z)
	terrain.grid_width = maxi(
		int(ceil((max_x - min_x) / cell_size)), 2,
	)
	terrain.grid_depth = maxi(
		int(ceil((max_z - min_z) / cell_size)), 2,
	)

	var total_cells: int = terrain.grid_width * terrain.grid_depth
	terrain.heights.resize(total_cells)
	terrain.zones.resize(total_cells)

	# Set biome on terrain so downstream systems can query it
	terrain.biome = biome

	# Resolve noise params from biome or defaults
	var amplitude: float = biome.terrain_amplitude \
		if biome else _DEFAULT_AMPLITUDE
	var frequency: float = biome.terrain_frequency \
		if biome else _DEFAULT_FREQUENCY
	var octaves: int = biome.noise_octaves \
		if biome else _DEFAULT_OCTAVES
	var lacunarity: float = biome.noise_lacunarity \
		if biome else _DEFAULT_LACUNARITY
	var gain: float = biome.noise_gain \
		if biome else _DEFAULT_GAIN
	var fw_flatten: float = biome.fairway_flatten_strength \
		if biome else _DEFAULT_FW_FLATTEN
	var green_radius: float = biome.green_flatten_radius \
		if biome else _DEFAULT_GREEN_RADIUS
	var tee_radius: float = biome.tee_flatten_radius \
		if biome else _DEFAULT_TEE_RADIUS
	var min_h: float = biome.min_height \
		if biome else _DEFAULT_MIN_HEIGHT
	var max_h: float = biome.max_height \
		if biome else _DEFAULT_MAX_HEIGHT

	var width_var: float = biome.fairway_width_variation \
		if biome else 0.0

	# --- Step 1: Paint zones (spatial rules only) ---
	_paint_zones(
		terrain, spine, tee_pos, cup_pos,
		fairway_width, width_var,
	)

	# --- Step 2: Noise-based heightmap ---
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = lacunarity
	noise.fractal_gain = gain

	_fill_noise(terrain, noise, ground_height, amplitude)

	# --- Step 3: Per-zone height modifiers ---
	if biome:
		_apply_zone_height_modifiers(terrain, biome, ground_height)

	# --- Step 2b: Update spine Y to follow terrain noise ---
	# Without this, fairway carving blends everything toward a flat plane.
	# Sampling noise at spine points makes the fairway undulate naturally.
	for i: int in range(spine.size()):
		var pt: Vector3 = spine[i]
		var sampled_h: float = ground_height + noise.get_noise_2d(pt.x, pt.z) * amplitude
		# Blend: keep some ground_height influence so tee/green stay reasonable
		spine[i].y = lerpf(ground_height, sampled_h, 0.7)

	# --- Step 3b: Plateau reshaping ---
	var plateau_factor: float = biome.plateau_factor if biome else 0.0
	if plateau_factor > 0.0:
		var plateau_levels: int = biome.plateau_levels if biome else 3
		_apply_plateaus(terrain, min_h, max_h, plateau_factor, plateau_levels)

	# --- Step 3c: Terrain archetype shaping ---
	if biome:
		var archetype_seed: int = rng.randi()
		_apply_archetype(
			terrain, spine, biome, archetype_seed,
			ground_height, fairway_width,
		)

	# --- Step 3d: Bowl setpieces (deep circular depressions near spine) ---
	var bowl_seed: int = rng.randi()
	_place_bowl_setpieces(
		terrain, spine, bowl_seed, ground_height, fairway_width,
	)

	# --- Step 3e: Inter-curve features (hills, ponds between S-curve legs) ---
	var ic_density: float = biome.inter_curve_density \
		if biome else 0.0
	if ic_density > 0.0:
		var ic_seed: int = rng.randi()
		_apply_inter_curve_features(
			terrain, spine, ic_seed, ground_height,
			fairway_width, amplitude, ic_density,
			biome.water_height if biome else -999.0,
		)

	# --- Step 4: Carve fairway corridor ---
	_carve_fairway(
		terrain, spine, fairway_width, fw_flatten,
		ground_height, width_var,
	)

	# --- Step 4b: Re-submerge island gaps (fairway carving may have filled them) ---
	_resubmerge_island_gaps(terrain)

	# --- Step 4c: Discontinuous fairway gaps ---
	if biome and biome.discontinuous_fairway:
		var gap_seed: int = rng.randi()
		_punch_fairway_gaps(terrain, spine, gap_seed, fairway_width)

	# --- Step 5: Flatten green and tee areas ---
	var tee_flat := Vector3(tee_pos.x, 0.0, tee_pos.z)
	var cup_flat := Vector3(cup_pos.x, 0.0, cup_pos.z)
	_flatten_area(terrain, cup_flat, green_radius, ground_height)
	_flatten_area(terrain, tee_flat, tee_radius, ground_height)

	# --- Step 6: Set hazard heights (needed by bunker clamping) ---
	if biome:
		terrain.water_height = biome.water_height
		terrain.lava_height = biome.lava_height

	# --- Step 7: Paint bunkers (zone + smooth bowl depression) ---
	if biome and bunkers.size() > 0:
		_paint_bunkers(terrain, bunkers, biome)

	# --- Step 8: Clamp heights ---
	_clamp_heights(terrain, min_h, max_h)

	# --- Step 9: Paint hazard zones (needs final heights) ---
	_paint_hazard_zones(terrain)

	# Set key positions with correct Y
	terrain.tee_position = Vector3(
		tee_pos.x, ground_height, tee_pos.z,
	)
	terrain.cup_position = Vector3(
		cup_pos.x, ground_height, cup_pos.z,
	)

	# --- Step 10: Cup depression (analytical bowl for putting physics) ---
	terrain.cup_depression_radius = 0.5
	terrain.cup_depression_depth = 0.5

	return terrain


# -------------------------------------------------------------------------
# Heightmap generation
# -------------------------------------------------------------------------

## Fill each cell with noise-based height centred on ground_height.
static func _fill_noise(
	terrain: RefCounted,
	noise: FastNoiseLite,
	ground_height: float,
	amplitude: float,
) -> void:
	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var h: float = ground_height \
				+ noise.get_noise_2d(world.x, world.z) * amplitude
			terrain.heights[terrain.idx(gx, gz)] = h


## Apply per-zone hill/valley scaling, shape exponents, and height offsets.
## Zones must already be painted before calling this.
static func _apply_zone_height_modifiers(
	terrain: RefCounted,
	biome: RefCounted,
	ground_height: float,
) -> void:
	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var cell_idx: int = terrain.idx(gx, gz)
			var zone_type: int = terrain.zones[cell_idx]
			var zone_def: ZoneDefinition = biome.get_zone_def(
				zone_type,
			)
			if not zone_def:
				continue

			var h: float = terrain.heights[cell_idx]
			var delta: float = h - ground_height

			if delta > 0.0:
				# Hill: apply shape exponent then scale
				delta = pow(delta, zone_def.hill_shape) \
					* zone_def.hill_scale
			elif delta < 0.0:
				# Valley: apply shape exponent then scale
				delta = -pow(
					absf(delta), zone_def.valley_shape,
				) * zone_def.valley_scale

			terrain.heights[cell_idx] = \
				ground_height + delta + zone_def.height_offset


## Snap heights toward discrete terrace levels to create flat-topped
## mesas with steep cliff transitions between elevation bands.
static func _apply_plateaus(
	terrain: RefCounted,
	min_h: float,
	max_h: float,
	factor: float,
	levels: int,
) -> void:
	var h_range: float = max_h - min_h
	if h_range < 0.01 or levels < 2:
		return
	var inv_range: float = 1.0 / h_range
	var levels_f: float = float(levels)
	for i: int in range(terrain.heights.size()):
		var h: float = terrain.heights[i]
		# Normalize to 0-1
		var t: float = clampf((h - min_h) * inv_range, 0.0, 1.0)
		# Snap to nearest terrace level
		var terrace_t: float = roundf(t * levels_f) / levels_f
		# Blend between original and snapped by plateau_factor
		var terraced_h: float = min_h + lerpf(t, terrace_t, factor) * h_range
		terrain.heights[i] = terraced_h


## Blend cells near the fairway spine toward the spine's elevation.
## Quadratic falloff: centre = full strength, edges blend into rough.
static func _carve_fairway(
	terrain: RefCounted,
	spine: Array[Vector3],
	fairway_width: float,
	flatten_strength: float,
	ground_height: float,
	width_variation: float = 0.0,
) -> void:
	# Pre-compute segment lengths for global t calculation
	var seg_lengths: Array[float] = []
	var spine_length: float = 0.0
	for i: int in range(spine.size() - 1):
		var sl: float = Vector3(
			spine[i + 1].x - spine[i].x, 0.0,
			spine[i + 1].z - spine[i].z,
		).length()
		seg_lengths.append(sl)
		spine_length += sl

	# Max carve reach (widest possible with variation)
	var max_fw: float = fairway_width * (
		1.0 + width_variation * 0.5
	)

	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var cell_idx: int = terrain.idx(gx, gz)
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var flat := Vector3(world.x, 0.0, world.z)

			var min_dist: float = INF
			var nearest_t: float = 0.0
			var nearest_seg: int = 0

			for i: int in range(spine.size() - 1):
				var a := Vector3(spine[i].x, 0.0, spine[i].z)
				var b := Vector3(
					spine[i + 1].x, 0.0, spine[i + 1].z,
				)
				var dist: float = _point_to_segment_distance_xz(
					flat, a, b,
				)
				if dist < min_dist:
					min_dist = dist
					nearest_seg = i
					var ab := b - a
					var ap := flat - a
					var ab_len_sq: float = ab.length_squared()
					nearest_t = clampf(
						ap.dot(ab) / maxf(ab_len_sq, 0.001),
						0.0, 1.0,
					)

			if min_dist < max_fw:
				# Compute global parametric t for width modulation
				var accum: float = 0.0
				for s: int in range(nearest_seg):
					accum += seg_lengths[s]
				accum += seg_lengths[nearest_seg] * nearest_t
				var global_t: float = accum / maxf(
					spine_length, 0.001,
				)

				var local_fw: float = fairway_width * \
					_width_multiplier(global_t, width_variation)

				if min_dist >= local_fw:
					continue

				var target_h: float = lerpf(
					spine[nearest_seg].y,
					spine[nearest_seg + 1].y,
					nearest_t,
				)
				if target_h == 0.0:
					target_h = ground_height

				var ratio: float = min_dist / local_fw
				var blend: float = \
					flatten_strength * (1.0 - ratio * ratio)
				terrain.heights[cell_idx] = lerpf(
					terrain.heights[cell_idx], target_h, blend,
				)


## Width multiplier at parametric t along spine.
## Two sine waves at different frequencies for organic width variation.
## Returns a multiplier in [1 - variation*0.5, 1 + variation*0.5].
static func _width_multiplier(t: float, variation: float) -> float:
	if variation <= 0.0:
		return 1.0
	var wave: float = (
		sin(t * PI * 3.0) * 0.6
		+ sin(t * PI * 7.0) * 0.4
	)
	return 1.0 + wave * variation * 0.5


## Flatten terrain in a circular area (for green / tee).
## Quadratic falloff: centre snaps to target_height, edges blend.
static func _flatten_area(
	terrain: RefCounted,
	center_xz: Vector3,
	radius: float,
	target_height: float,
) -> void:
	var radius_sq: float = radius * radius
	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var dx: float = world.x - center_xz.x
			var dz: float = world.z - center_xz.z
			var dist_sq: float = dx * dx + dz * dz
			if dist_sq < radius_sq:
				var ratio: float = sqrt(dist_sq) / radius
				var blend: float = 1.0 - ratio * ratio
				var cell_idx: int = terrain.idx(gx, gz)
				terrain.heights[cell_idx] = lerpf(
					terrain.heights[cell_idx],
					target_height, blend,
				)


## Clamp all heights to biome min/max range.
static func _clamp_heights(
	terrain: RefCounted,
	min_h: float,
	max_h: float,
) -> void:
	for i: int in range(terrain.heights.size()):
		terrain.heights[i] = clampf(
			terrain.heights[i], min_h, max_h,
		)


# -------------------------------------------------------------------------
# Zone painting
# -------------------------------------------------------------------------

static func _paint_zones(
	terrain: RefCounted,
	spine: Array[Vector3],
	tee_pos: Vector3,
	cup_pos: Vector3,
	fairway_width: float,
	width_variation: float = 0.0,
) -> void:
	var half_fw: float = fairway_width * 0.5
	var max_half_fw: float = half_fw * (
		1.0 + width_variation * 0.5
	)
	var green_radius_sq: float = 8.0 * 8.0  # GREEN_RADIUS
	var tee_radius_sq: float = 3.0 * 3.0    # tee box ~3m

	var cup_flat := Vector3(cup_pos.x, 0.0, cup_pos.z)
	var tee_flat := Vector3(tee_pos.x, 0.0, tee_pos.z)

	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var cell_idx: int = terrain.idx(gx, gz)
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var flat := Vector3(world.x, 0.0, world.z)

			var to_cup_sq: float = \
				flat.distance_squared_to(cup_flat)
			var to_tee_sq: float = \
				flat.distance_squared_to(tee_flat)

			if to_cup_sq <= green_radius_sq:
				terrain.zones[cell_idx] = \
					TerrainDataScript.ZoneType.GREEN
				continue

			if to_tee_sq <= tee_radius_sq:
				terrain.zones[cell_idx] = \
					TerrainDataScript.ZoneType.TEE
				continue

			# Distance + parametric t for width modulation
			if width_variation > 0.0:
				var dt: Array[float] = \
					PolylineUtilsScript.min_distance_and_t_xz(
						flat, spine,
					)
				var local_half: float = half_fw * \
					_width_multiplier(dt[1], width_variation)
				if dt[0] <= local_half:
					terrain.zones[cell_idx] = \
						TerrainDataScript.ZoneType.FAIRWAY
					continue
			else:
				var dist_to_spine: float = \
					PolylineUtilsScript.min_distance_xz(
						flat, spine,
					)
				if dist_to_spine <= half_fw:
					terrain.zones[cell_idx] = \
						TerrainDataScript.ZoneType.FAIRWAY
					continue

			terrain.zones[cell_idx] = \
				TerrainDataScript.ZoneType.ROUGH


## Reassign cells to WATER or LAVA based on final heights.
## Only overrides ROUGH and OOB — spatial zones (GREEN, TEE, FAIRWAY, BUNKER)
## are preserved so the green/tee never become submerged.
static func _paint_hazard_zones(terrain: RefCounted) -> void:
	var has_water: bool = terrain.water_height > -900.0
	var has_lava: bool = terrain.lava_height > -900.0
	if not has_water and not has_lava:
		return

	for i: int in range(terrain.heights.size()):
		var zone: int = terrain.zones[i]
		# Only override rough and OOB
		if zone != TerrainDataScript.ZoneType.ROUGH \
			and zone != TerrainDataScript.ZoneType.OOB:
			continue
		var h: float = terrain.heights[i]
		# Lava takes priority over water (checked first)
		if has_lava and h < terrain.lava_height:
			terrain.zones[i] = TerrainDataScript.ZoneType.LAVA
		elif has_water and h < terrain.water_height:
			terrain.zones[i] = TerrainDataScript.ZoneType.WATER


# -------------------------------------------------------------------------
# Bunker painting
# -------------------------------------------------------------------------

## Paint BUNKER zones at the given positions and carve smooth bowl
## depressions. Runs after fairway carving + green/tee flattening so
## the bowls are relative to the already-smooth terrain surface.
## Supports elliptical bunkers via aspect_ratio and rotation on each
## descriptor.
static func _paint_bunkers(
	terrain: RefCounted,
	bunkers: Array,
	biome: RefCounted,
) -> void:
	var zone_def: ZoneDefinition = biome.get_zone_def(
		TerrainDataScript.ZoneType.BUNKER,
	)
	# Depression depth — minimum 1.2 so bunkers are clearly visible
	var depth: float = maxf(
		absf(zone_def.height_offset) if zone_def else 1.2, 1.2,
	)
	# Floor height — don't depress bunkers below water/lava planes
	var floor_h: float = -999.0
	if terrain.water_height > -900.0:
		floor_h = maxf(floor_h, terrain.water_height + 0.15)
	if terrain.lava_height > -900.0:
		floor_h = maxf(floor_h, terrain.lava_height + 0.15)

	for bunker in bunkers:
		var cx: float = bunker.world_position.x
		var cz: float = bunker.world_position.z
		var radius: float = bunker.radius
		var aspect: float = bunker.aspect_ratio \
			if "aspect_ratio" in bunker else 1.0
		var rot: float = bunker.rotation \
			if "rotation" in bunker else 0.0

		# Precompute rotation for ellipse distance check
		var cos_r: float = cos(-rot)
		var sin_r: float = sin(-rot)
		# Semi-axes: long = radius * aspect, short = radius
		var semi_long: float = radius * aspect
		var semi_short: float = radius
		# Bounding radius for early rejection
		var bound_sq: float = semi_long * semi_long

		# Reference height at bunker center
		var center_gx: int = clampi(
			int((cx - terrain.origin.x) / terrain.cell_size),
			0, terrain.grid_width - 1,
		)
		var center_gz: int = clampi(
			int((cz - terrain.origin.z) / terrain.cell_size),
			0, terrain.grid_depth - 1,
		)
		var center_h: float = terrain.heights[
			terrain.idx(center_gx, center_gz)
		]

		for gz: int in range(terrain.grid_depth):
			for gx: int in range(terrain.grid_width):
				var world: Vector3 = terrain.grid_to_world(
					gx, gz,
				)
				var dx: float = world.x - cx
				var dz: float = world.z - cz

				# Early reject with bounding circle
				if dx * dx + dz * dz > bound_sq:
					continue

				# Rotate into ellipse-local space
				var lx: float = dx * cos_r - dz * sin_r
				var lz: float = dx * sin_r + dz * cos_r

				# Normalized ellipse distance (1.0 = on edge)
				var ellipse_d: float = (
					(lx * lx) / (semi_long * semi_long)
					+ (lz * lz) / (semi_short * semi_short)
				)
				if ellipse_d >= 1.0:
					continue

				var cell_idx: int = terrain.idx(gx, gz)
				var zone: int = terrain.zones[cell_idx]

				# Don't override green or tee zones
				if zone == TerrainDataScript.ZoneType.GREEN \
					or zone == TerrainDataScript.ZoneType.TEE:
					continue

				terrain.zones[cell_idx] = \
					TerrainDataScript.ZoneType.BUNKER

				# Bowl depression — smoothstep from edge
				var dist_ratio: float = sqrt(ellipse_d)
				var bowl: float = 1.0 - smoothstep(
					0.0, 1.0, dist_ratio,
				)

				# Blend interior toward center height
				# (smooths noise) then apply depression
				var h: float = terrain.heights[cell_idx]
				var smoothed: float = lerpf(
					h, center_h, bowl * 0.7,
				)
				var depressed: float = smoothed - depth * bowl
				# Keep bunkers above water/lava planes
				if floor_h > -900.0:
					depressed = maxf(depressed, floor_h)
				terrain.heights[cell_idx] = depressed


# -------------------------------------------------------------------------
# Bowl setpieces
# -------------------------------------------------------------------------

## Place 1-3 deep circular bowl depressions near the spine (offset laterally).
## These create dramatic landscape features between fairway curves — like
## the deep pits visible in Super Battle Golf desert courses.
## Bowls avoid tee (t < 0.15) and green (t > 0.85) areas.
static func _place_bowl_setpieces(
	terrain: RefCounted,
	spine: Array[Vector3],
	bowl_seed: int,
	_ground_height: float,
	fairway_width: float,
) -> void:
	var bowl_rng := RandomNumberGenerator.new()
	bowl_rng.seed = bowl_seed

	var spine_length: float = PolylineUtilsScript.total_length(spine)
	if spine_length < 80.0:
		return  # too short for bowls

	# Number of bowls scales with course length
	var num_bowls: int = bowl_rng.randi_range(1, clampi(int(spine_length / 120.0), 1, 4))

	for _b: int in range(num_bowls):
		# Pick a position along the spine, avoiding tee/green
		var t: float = bowl_rng.randf_range(0.2, 0.8)
		var center: Vector3 = PolylineUtilsScript.sample_position(spine, t)
		var seg_dir: Vector3 = PolylineUtilsScript.sample_direction(spine, t)
		var seg_right: Vector3 = PolylineUtilsScript.direction_to_right(seg_dir)

		# Offset laterally from spine so bowl sits beside the fairway
		var lateral_offset: float = bowl_rng.randf_range(
			fairway_width * 0.8, fairway_width * 1.5,
		)
		var side: float = 1.0 if bowl_rng.randf() > 0.5 else -1.0
		center += seg_right * lateral_offset * side

		# Bowl dimensions
		var radius: float = bowl_rng.randf_range(
			fairway_width * 0.6, fairway_width * 1.2,
		)
		var depth: float = bowl_rng.randf_range(4.0, 8.0)

		# Carve the bowl depression
		for gz: int in range(terrain.grid_depth):
			for gx: int in range(terrain.grid_width):
				var world: Vector3 = terrain.grid_to_world(gx, gz)
				var dx: float = world.x - center.x
				var dz: float = world.z - center.z
				var dist_sq: float = dx * dx + dz * dz
				var radius_sq: float = radius * radius

				if dist_sq >= radius_sq:
					continue

				var cell_idx: int = terrain.idx(gx, gz)
				var dist: float = sqrt(dist_sq)
				var norm: float = dist / radius

				# Smooth bowl shape — deepest at center
				var bowl_factor: float = 1.0 - smoothstep(0.0, 1.0, norm)
				var depression: float = depth * bowl_factor

				terrain.heights[cell_idx] -= depression

				# Rim lip — slight raise at edge for dramatic effect
				if norm > 0.7 and norm < 1.0:
					var rim_t: float = (norm - 0.7) / 0.3
					var rim: float = sin(rim_t * PI) * depth * 0.15
					terrain.heights[cell_idx] += rim


# -------------------------------------------------------------------------
# Inter-curve features (hills, ponds, terrain between S-curve legs)
# -------------------------------------------------------------------------

## Detect areas between non-adjacent spine legs and add environmental
## features: amplified hills, water pocket depressions, and terrain variety.
static func _apply_inter_curve_features(
	terrain: RefCounted,
	spine: Array[Vector3],
	rng_seed: int,
	ground_height: float,
	fairway_width: float,
	base_amplitude: float,
	density: float,
	water_height: float,
) -> void:
	var ic_rng := RandomNumberGenerator.new()
	ic_rng.seed = rng_seed

	var seg_count: int = spine.size() - 1
	if seg_count < 3:
		return  # Need at least 3 segments for inter-curve areas

	var adj_threshold: int = maxi(2, seg_count / 3)
	var detect_range: float = fairway_width * 4.0
	var half_fw: float = fairway_width * 0.5

	# Secondary noise for inter-curve terrain variety
	var ic_noise := FastNoiseLite.new()
	ic_noise.seed = rng_seed + 777
	ic_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ic_noise.frequency = 0.025
	ic_noise.fractal_octaves = 3

	# Pond noise — low frequency for large water pockets
	var pond_noise := FastNoiseLite.new()
	pond_noise.seed = rng_seed + 1234
	pond_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pond_noise.frequency = 0.012

	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var cell_idx: int = terrain.idx(gx, gz)
			var flat := Vector3(world.x, 0.0, world.z)

			# Find nearest segment
			var nearest_dist: float = INF
			var nearest_seg: int = 0
			for i: int in range(seg_count):
				var a := Vector3(
					spine[i].x, 0.0, spine[i].z,
				)
				var b := Vector3(
					spine[i + 1].x, 0.0, spine[i + 1].z,
				)
				var dist: float = \
					_point_to_segment_distance_xz(flat, a, b)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_seg = i

			# Skip cells on or very near the fairway
			if nearest_dist < half_fw * 1.2:
				continue

			# Check for non-adjacent parallel leg
			var has_parallel: bool = false
			for i: int in range(seg_count):
				if absi(i - nearest_seg) <= adj_threshold:
					continue
				var a := Vector3(
					spine[i].x, 0.0, spine[i].z,
				)
				var b := Vector3(
					spine[i + 1].x, 0.0,
					spine[i + 1].z,
				)
				var dist: float = \
					_point_to_segment_distance_xz(flat, a, b)
				if dist < detect_range:
					has_parallel = true
					break

			if not has_parallel:
				continue

			# This cell is between S-curve legs — add features
			var wx: float = world.x
			var wz: float = world.z

			# Hills: amplified elevation with secondary noise
			var hill_val: float = ic_noise.get_noise_2d(wx, wz)
			var hill_boost: float = hill_val * base_amplitude \
				* 2.5 * density
			terrain.heights[cell_idx] += hill_boost

			# Water pockets: depress some areas below water_height
			if water_height > -900.0:
				var pond_val: float = pond_noise.get_noise_2d(
					wx, wz,
				)
				# pond_val < -0.2 creates pockets; density controls
				# threshold (higher density = more ponds)
				var pond_thresh: float = lerpf(
					-0.5, -0.15, density,
				)
				if pond_val < pond_thresh:
					var pond_depth: float = (
						pond_thresh - pond_val
					) * 8.0 * density
					var target_h: float = water_height \
						- pond_depth
					terrain.heights[cell_idx] = minf(
						terrain.heights[cell_idx], target_h,
					)


# -------------------------------------------------------------------------
# Discontinuous fairway
# -------------------------------------------------------------------------

## Punch 1-3 gaps in the fairway — depresses terrain to create real
## physical breaks (water-filled chasms) that the player must hit across.
## Gaps avoid tee (t < 0.15) and green (t > 0.85) areas.
static func _punch_fairway_gaps(
	terrain: RefCounted,
	spine: Array[Vector3],
	gap_seed: int,
	fairway_width: float,
) -> void:
	var gap_rng := RandomNumberGenerator.new()
	gap_rng.seed = gap_seed

	var num_gaps: int = gap_rng.randi_range(1, 3)
	var gap_width: float = gap_rng.randf_range(10.0, 20.0)

	# Depression target — sink below water if available, otherwise deep drop
	var water_h: float = terrain.water_height if terrain.water_height > -900.0 else -2.0
	var sink_height: float = water_h - 1.5

	for _b: int in range(num_gaps):
		var gap_t: float = gap_rng.randf_range(0.2, 0.8)
		var gap_center: Vector3 = PolylineUtilsScript.sample_position(
			spine, gap_t,
		)
		var gap_dir: Vector3 = PolylineUtilsScript.sample_direction(
			spine, gap_t,
		)
		var half_gap: float = gap_width * 0.5

		# Gap is a perpendicular strip across the fairway + surrounding area
		for gz: int in range(terrain.grid_depth):
			for gx: int in range(terrain.grid_width):
				var world: Vector3 = terrain.grid_to_world(gx, gz)
				var cell_idx: int = terrain.idx(gx, gz)
				var zone: int = terrain.zones[cell_idx]

				# Skip green and tee zones
				if zone == TerrainDataScript.ZoneType.GREEN \
					or zone == TerrainDataScript.ZoneType.TEE:
					continue

				var offset := Vector3(
					world.x - gap_center.x, 0.0, world.z - gap_center.z,
				)
				# Distance along the fairway direction
				var along_dist: float = absf(
					offset.x * gap_dir.x + offset.z * gap_dir.z,
				)
				if along_dist > half_gap:
					continue

				# Lateral distance from spine
				var lateral_dist: float = absf(
					offset.x * (-gap_dir.z) + offset.z * gap_dir.x,
				)
				if lateral_dist > fairway_width * 0.8:
					continue

				# Smoothstep falloff from gap center for natural edges
				var along_norm: float = along_dist / half_gap
				var depression_strength: float = 1.0 - smoothstep(
					0.6, 1.0, along_norm,
				)

				# Depress terrain
				terrain.heights[cell_idx] = lerpf(
					terrain.heights[cell_idx],
					sink_height,
					depression_strength,
				)

				# Revert fairway zone to ROUGH (becomes WATER in hazard pass)
				if zone == TerrainDataScript.ZoneType.FAIRWAY \
					and depression_strength > 0.3:
					terrain.zones[cell_idx] = \
						TerrainDataScript.ZoneType.ROUGH


# -------------------------------------------------------------------------
# Geometry helpers
# -------------------------------------------------------------------------

# -------------------------------------------------------------------------
# Terrain archetype shaping
# -------------------------------------------------------------------------

## Dispatch to the appropriate archetype shaping function.
static func _apply_archetype(
	terrain: RefCounted,
	spine: Array[Vector3],
	biome: RefCounted,
	archetype_seed: int,
	ground_height: float,
	fairway_width: float,
) -> void:
	match biome.terrain_archetype:
		1:  # ISLAND
			var arch_rng := RandomNumberGenerator.new()
			arch_rng.seed = archetype_seed
			_apply_island_mask(
				terrain, spine, biome, arch_rng,
				ground_height, fairway_width,
			)
		2:  # VALLEY_CORRIDOR
			_apply_valley_corridor(
				terrain, spine, biome, ground_height, fairway_width,
			)
		3:  # DONUT_LAKE
			var arch_rng := RandomNumberGenerator.new()
			arch_rng.seed = archetype_seed
			_apply_donut_lake(
				terrain, spine, biome, arch_rng,
				ground_height, fairway_width,
			)
		4:  # ASCENDING_PLATEAU
			_apply_ascending_plateau(
				terrain, spine, biome, ground_height, fairway_width,
			)
		_:  # CONTINENTAL (0) — no special shaping
			pass


## ISLAND archetype — lower everything below water, raise distinct island
## landmasses. No bridges — water gaps between islands force the player
## to hit across. Stores island data on terrain for post-carve re-submersion.
static func _apply_island_mask(
	terrain: RefCounted,
	spine: Array[Vector3],
	biome: RefCounted,
	rng: RandomNumberGenerator,
	ground_height: float,
	fairway_width: float,
) -> void:
	var water_h: float = biome.water_height if biome.water_height > -900.0 else 0.0
	var base_height: float = water_h - 2.0  # submerge everything

	# Generate island centers along spine
	var island_count: int = biome.island_count
	var islands: Array[Dictionary] = []
	for idx: int in range(island_count):
		var t: float = float(idx) / float(maxi(island_count - 1, 1))
		t += rng.randf_range(-0.08, 0.08)
		t = clampf(t, 0.0, 1.0)

		var center: Vector3 = PolylineUtilsScript.sample_position(spine, t)
		# Slight lateral offset for visual interest
		var seg_dir: Vector3 = PolylineUtilsScript.sample_direction(spine, t)
		var seg_right: Vector3 = PolylineUtilsScript.direction_to_right(seg_dir)
		center += seg_right * rng.randf_range(
			-fairway_width * 0.3, fairway_width * 0.3,
		)

		var radius: float = rng.randf_range(
			biome.island_radius_min, biome.island_radius_max,
		)
		# Tee and green islands are larger
		if idx == 0 or idx == island_count - 1:
			radius *= 1.3
		islands.append({center = center, radius = radius})

	# Store island data on terrain for post-carve re-submersion
	terrain.set_meta(&"island_data", islands)
	terrain.set_meta(&"island_base_height", base_height)

	# Apply island mask to terrain — no bridges, only islands
	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var cell_idx: int = terrain.idx(gx, gz)
			var original_h: float = terrain.heights[cell_idx]
			var max_influence: float = 0.0

			# Check island influence only (no bridges)
			for island: Dictionary in islands:
				var ic: Vector3 = island.center
				var dist: float = Vector3(
					world.x - ic.x, 0.0, world.z - ic.z,
				).length()
				var norm_dist: float = dist / island.radius
				if norm_dist < 1.0:
					var influence: float = 1.0 - smoothstep(
						0.0, 1.0, norm_dist,
					)
					max_influence = maxf(max_influence, influence)

			if max_influence > 0.0:
				# Raise from submerged to original noise height scaled by influence
				var target_h: float = ground_height + (
					original_h - ground_height
				) * 0.7
				target_h = maxf(target_h, water_h + 0.5)  # at least above water
				terrain.heights[cell_idx] = lerpf(
					base_height, target_h, max_influence,
				)
			else:
				terrain.heights[cell_idx] = base_height


## Re-submerge cells between islands after fairway carving.
## Fairway carving raises terrain along the spine, which fills in water gaps.
## This pass re-sinks any cell that isn't on an island back below water.
static func _resubmerge_island_gaps(terrain: RefCounted) -> void:
	if not terrain.has_meta(&"island_data"):
		return
	var islands: Array = terrain.get_meta(&"island_data")
	var base_height: float = terrain.get_meta(&"island_base_height")

	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var cell_idx: int = terrain.idx(gx, gz)

			var on_island: bool = false
			for island: Dictionary in islands:
				var ic: Vector3 = island.center
				var dist: float = Vector3(
					world.x - ic.x, 0.0, world.z - ic.z,
				).length()
				if dist < island.radius:
					on_island = true
					break

			if not on_island:
				terrain.heights[cell_idx] = base_height
				# Revert fairway zone to ROUGH (will become WATER in hazard pass)
				if terrain.zones[cell_idx] == TerrainDataScript.ZoneType.FAIRWAY:
					terrain.zones[cell_idx] = TerrainDataScript.ZoneType.ROUGH


## VALLEY_CORRIDOR archetype — high ridges with carved winding valley.
## For S-curved spines, blocking ridges are raised between non-adjacent
## parallel legs so the player can't fire directly across bends.
static func _apply_valley_corridor(
	terrain: RefCounted,
	spine: Array[Vector3],
	biome: RefCounted,
	ground_height: float,
	fairway_width: float,
) -> void:
	var corridor_width: float = \
		fairway_width * biome.corridor_width_multiplier
	var ridge_h: float = biome.ridge_height
	var steepness: float = biome.wall_steepness
	var transition_w: float = \
		corridor_width * (1.0 - steepness) * 0.5 + 2.0

	var seg_count: int = spine.size() - 1
	# How many segment indices apart counts as "non-adjacent"
	var adj_threshold: int = maxi(2, seg_count / 3)
	# XZ detection range for a parallel leg
	var detect_range: float = corridor_width * 3.0
	# Don't block cells very close to nearest segment (on the fairway)
	var block_min_dist: float = corridor_width * 0.5

	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var cell_idx: int = terrain.idx(gx, gz)
			var original_h: float = terrain.heights[cell_idx]
			var flat := Vector3(world.x, 0.0, world.z)

			# Find nearest segment + check for non-adjacent parallel
			var nearest_dist: float = INF
			var nearest_seg: int = 0
			var has_parallel: bool = false

			for i: int in range(seg_count):
				var a := Vector3(
					spine[i].x, 0.0, spine[i].z,
				)
				var b := Vector3(
					spine[i + 1].x, 0.0, spine[i + 1].z,
				)
				var dist: float = \
					_point_to_segment_distance_xz(flat, a, b)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_seg = i

			# Check for non-adjacent segment also close
			if nearest_dist > block_min_dist:
				for i: int in range(seg_count):
					if absi(i - nearest_seg) <= adj_threshold:
						continue
					var a := Vector3(
						spine[i].x, 0.0, spine[i].z,
					)
					var b := Vector3(
						spine[i + 1].x, 0.0,
						spine[i + 1].z,
					)
					var dist: float = \
						_point_to_segment_distance_xz(
							flat, a, b,
						)
					if dist < detect_range:
						has_parallel = true
						break

			if has_parallel:
				# Between two parallel legs — raise blocking ridge
				var ridge_top: float = ground_height + ridge_h + (
					original_h - ground_height
				) * 0.3
				# Smooth transition from valley edge to ridge peak
				var edge_t: float = clampf(
					(nearest_dist - block_min_dist)
					/ (corridor_width - block_min_dist),
					0.0, 1.0,
				)
				var blend: float = smoothstep(0.0, 1.0, edge_t)
				var floor_h: float = \
					ground_height + (
						original_h - ground_height
					) * 0.15
				terrain.heights[cell_idx] = lerpf(
					floor_h, ridge_top, blend,
				)
				continue

			if nearest_dist <= corridor_width:
				# Valley floor: gentle noise
				var floor_noise: float = (
					original_h - ground_height
				) * 0.15
				terrain.heights[cell_idx] = \
					ground_height + floor_noise
			elif nearest_dist <= corridor_width + transition_w:
				# Transition: steep blend from floor to ridge
				var t: float = (
					nearest_dist - corridor_width
				) / transition_w
				var blend: float = smoothstep(0.0, 1.0, t)
				var floor_h: float = ground_height
				var top_h: float = ground_height + ridge_h + (
					original_h - ground_height
				) * 0.5
				terrain.heights[cell_idx] = lerpf(
					floor_h, top_h, blend,
				)
			else:
				# Ridge: raised terrain + dampened noise
				terrain.heights[cell_idx] = \
					ground_height + ridge_h + (
						original_h - ground_height
					) * 0.5


## DONUT_LAKE archetype — central water body with a raised green island in
## the middle. Fairway ring wraps around the lake; a narrow land bridge
## connects the ring to the central green. The cup sits on the center island.
static func _apply_donut_lake(
	terrain: RefCounted,
	spine: Array[Vector3],
	biome: RefCounted,
	rng: RandomNumberGenerator,
	ground_height: float,
	fairway_width: float,
) -> void:
	var water_h: float = biome.water_height if biome.water_height > -900.0 else 0.0
	var lake_depth: float = biome.lake_depth

	# The cup (last spine point) is in the center; compute ring center from it
	var center: Vector3 = spine[spine.size() - 1]

	var lake_radius: float = rng.randf_range(
		biome.lake_radius_min, biome.lake_radius_max,
	)

	# Central green island radius — small platform for the cup
	var green_island_radius: float = biome.green_flatten_radius \
		if biome else 10.0
	green_island_radius = maxf(green_island_radius, 8.0)

	# The ring fairway sits outside the lake; compute outer ring boundary
	var ring_inner: float = lake_radius
	var ring_outer: float = lake_radius + fairway_width * 2.5

	# Land bridge from ring to center island — along the last spine segment
	var bridge_dir := Vector3.ZERO
	if spine.size() >= 2:
		bridge_dir = (
			center - spine[spine.size() - 2]
		)
		bridge_dir.y = 0.0
		bridge_dir = bridge_dir.normalized()
	var bridge_half_width: float = fairway_width * 0.4

	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var cell_idx: int = terrain.idx(gx, gz)
			var original_h: float = terrain.heights[cell_idx]

			var dx: float = world.x - center.x
			var dz: float = world.z - center.z
			var dist: float = sqrt(dx * dx + dz * dz)

			# Check if on the central green island
			if dist < green_island_radius:
				var norm: float = dist / green_island_radius
				var infl: float = 1.0 - smoothstep(0.8, 1.0, norm)
				terrain.heights[cell_idx] = lerpf(
					water_h - lake_depth, ground_height + 0.3, infl,
				)
				continue

			# Check if on the land bridge to center
			if bridge_dir.length_squared() > 0.01 and dist < ring_inner:
				var to_cell := Vector3(dx, 0.0, dz).normalized()
				# Perpendicular distance from bridge center line
				var perp: float = absf(
					to_cell.x * (-bridge_dir.z) + to_cell.z * bridge_dir.x,
				) * dist
				# Along bridge direction (positive = toward center)
				var along: float = (
					to_cell.x * bridge_dir.x + to_cell.z * bridge_dir.z
				) * dist
				if perp < bridge_half_width and along > 0.0:
					var bridge_norm: float = perp / bridge_half_width
					var bridge_infl: float = 1.0 - smoothstep(
						0.6, 1.0, bridge_norm,
					)
					terrain.heights[cell_idx] = lerpf(
						water_h - lake_depth, ground_height, bridge_infl,
					)
					continue

			# Inside the lake ring (between green island and fairway ring)
			if dist < ring_inner:
				var norm: float = (dist - green_island_radius) / maxf(
					ring_inner - green_island_radius, 1.0,
				)
				norm = clampf(norm, 0.0, 1.0)
				# Bowl shape — deeper in the middle of the lake ring
				var bowl: float = sin(norm * PI) * 0.7 + 0.3
				terrain.heights[cell_idx] = water_h - lake_depth * bowl
				continue

			# On or near the fairway ring
			if dist < ring_outer:
				# Keep original terrain (fairway ring is normal ground)
				pass
			else:
				# Outside the ring — gentle terrain, slightly lower
				var outer_norm: float = (dist - ring_outer) / (
					ring_outer * 0.5
				)
				outer_norm = clampf(outer_norm, 0.0, 1.0)
				terrain.heights[cell_idx] = lerpf(
					original_h, original_h * 0.6, outer_norm,
				)


## ASCENDING_PLATEAU archetype — discrete puzzle-piece platforms at
## increasing elevations with steep cliff drops between them.
## Each platform is a distinct landmass — like stacked mesas.
static func _apply_ascending_plateau(
	terrain: RefCounted,
	spine: Array[Vector3],
	biome: RefCounted,
	ground_height: float,
	fairway_width: float,
) -> void:
	var step_count: int = biome.step_count
	var step_h: float = biome.step_height
	var height_var: float = biome.step_height_variation
	var steepness: float = biome.step_steepness
	var platform_scale: float = biome.step_platform_scale

	# Use a deterministic sub-RNG for per-platform variation
	# (seeded from terrain noise seed stored on terrain)
	var plat_rng := RandomNumberGenerator.new()
	plat_rng.seed = terrain.heights.size()  # stable seed from grid size

	# Build platform definitions: each has a center, radius, and elevation
	var platforms: Array[Dictionary] = []
	var cumulative_h: float = 0.0
	for idx: int in range(step_count):
		var t: float = float(idx) / float(maxi(step_count - 1, 1))
		var center: Vector3 = PolylineUtilsScript.sample_position(spine, t)
		# Platform radius from biome param; tee/cup platforms larger
		var radius: float = fairway_width * platform_scale
		if idx == 0 or idx == step_count - 1:
			radius *= 1.3
		# Per-step height variation
		var this_step_h: float = step_h
		if idx > 0:
			this_step_h += plat_rng.randf_range(-height_var, height_var)
			this_step_h = maxf(this_step_h, 1.0)  # at least 1m rise
		cumulative_h += this_step_h if idx > 0 else 0.0
		platforms.append({
			center = center,
			radius = radius,
			elevation = ground_height + cumulative_h,
		})

	# Base level: lowest terrain between platforms
	var base_level: float = ground_height - step_h * 0.5

	# Cliff edge start — steepness controls how sharp the drop-off is
	# steepness=1 → cliff starts at 0.9 (very sharp), steepness=0 → starts at 0.4 (gentle)
	var cliff_start: float = lerpf(0.4, 0.9, steepness)

	# Narrow connection paths between adjacent platforms
	var connection_width: float = fairway_width * 0.6

	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var cell_idx: int = terrain.idx(gx, gz)
			var original_h: float = terrain.heights[cell_idx]
			var flat := Vector3(world.x, 0.0, world.z)

			# Find strongest platform influence
			var best_elevation: float = base_level
			var best_influence: float = 0.0

			for plat: Dictionary in platforms:
				var pc: Vector3 = plat.center
				var dist: float = Vector3(
					world.x - pc.x, 0.0, world.z - pc.z,
				).length()
				var norm: float = dist / plat.radius
				if norm < 1.0:
					# Hard-edged smoothstep for cliff-like drop-off
					var infl: float = 1.0 - smoothstep(cliff_start, 1.0, norm)
					if infl > best_influence:
						best_influence = infl
						best_elevation = plat.elevation

			# Check connection paths between adjacent platforms
			for idx: int in range(platforms.size() - 1):
				var p_a: Dictionary = platforms[idx]
				var p_b: Dictionary = platforms[idx + 1]
				var a_flat := Vector3(p_a.center.x, 0.0, p_a.center.z)
				var b_flat := Vector3(p_b.center.x, 0.0, p_b.center.z)
				var dist_to_path: float = _point_to_segment_distance_xz(
					flat, a_flat, b_flat,
				)
				if dist_to_path < connection_width:
					# Find t along connection to interpolate elevation
					var ab: Vector3 = b_flat - a_flat
					var ap: Vector3 = flat - a_flat
					var path_t: float = clampf(
						ap.dot(ab) / maxf(ab.length_squared(), 0.001),
						0.0, 1.0,
					)
					var path_elev: float = lerpf(
						p_a.elevation, p_b.elevation, path_t,
					)
					var path_norm: float = dist_to_path / connection_width
					var path_infl: float = 1.0 - smoothstep(
						cliff_start * 0.85, 1.0, path_norm,
					)
					if path_infl > best_influence:
						best_influence = path_infl
						best_elevation = path_elev

			if best_influence > 0.01:
				# On a platform or connection: flat with slight noise
				var noise_frac: float = (original_h - ground_height) * 0.08
				var target_h: float = best_elevation + noise_frac
				# Cliff edge blend
				var cliff_blend: float = smoothstep(0.0, 1.0, best_influence)
				terrain.heights[cell_idx] = lerpf(
					base_level, target_h, cliff_blend,
				)
			else:
				# Between platforms: drop to base level
				terrain.heights[cell_idx] = base_level + (
					original_h - ground_height
				) * 0.15


## Returns the XZ-plane distance from a point to a line segment.
static func _point_to_segment_distance_xz(
	point: Vector3, seg_a: Vector3, seg_b: Vector3,
) -> float:
	var ab := Vector3(
		seg_b.x - seg_a.x, 0.0, seg_b.z - seg_a.z,
	)
	var ap := Vector3(
		point.x - seg_a.x, 0.0, point.z - seg_a.z,
	)
	var ab_len_sq: float = ab.x * ab.x + ab.z * ab.z
	if ab_len_sq < 0.001:
		return ap.length()
	var t: float = clampf(
		(ap.x * ab.x + ap.z * ab.z) / ab_len_sq, 0.0, 1.0,
	)
	var closest := Vector3(
		seg_a.x + ab.x * t, 0.0, seg_a.z + ab.z * t,
	)
	return Vector3(
		point.x - closest.x, 0.0, point.z - closest.z,
	).length()
