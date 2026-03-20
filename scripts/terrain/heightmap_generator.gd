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
##   6. Clamp heights to biome min/max
class_name HeightmapGenerator
extends RefCounted

const TerrainDataScript = preload("res://scripts/terrain/terrain_data.gd")
const BiomeDefinitionScript = preload("res://resources/biome_definition.gd")

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
## Pass a BiomeDefinition to use its noise/elevation/zone params;
## null falls back to hardcoded defaults.
static func generate(
	rng: RandomNumberGenerator,
	tee_pos: Vector3,
	cup_pos: Vector3,
	hole_direction: float,
	hole_length: float,
	fairway_width: float,
	ground_height: float = 0.5,
	cell_size: float = 2.0,
	margin: float = 30.0,
	biome: BiomeDefinition = null,
) -> RefCounted:
	var noise_seed: int = rng.randi()

	var terrain: RefCounted = TerrainDataScript.new()
	terrain.cell_size = cell_size

	# Compute grid bounds — AABB around the rotated hole + margin
	var dir := Vector3(
		sin(hole_direction), 0.0, -cos(hole_direction),
	)
	var right := Vector3(
		cos(hole_direction), 0.0, sin(hole_direction),
	)

	var spine: Array[Vector3] = [
		Vector3(tee_pos.x, ground_height, tee_pos.z),
		Vector3(cup_pos.x, ground_height, cup_pos.z),
	]
	terrain.fairway_spine = spine

	var half_fw: float = fairway_width * 0.5 + margin
	var corners: Array[Vector3] = [
		tee_pos + right * half_fw - dir * margin,
		tee_pos - right * half_fw - dir * margin,
		tee_pos + dir * (hole_length + margin) + right * half_fw,
		tee_pos + dir * (hole_length + margin) - right * half_fw,
	]

	var min_x: float = corners[0].x
	var max_x: float = corners[0].x
	var min_z: float = corners[0].z
	var max_z: float = corners[0].z
	for c: Vector3 in corners:
		min_x = minf(min_x, c.x)
		max_x = maxf(max_x, c.x)
		min_z = minf(min_z, c.z)
		max_z = maxf(max_z, c.z)

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

	# --- Step 1: Paint zones (spatial rules only) ---
	_paint_zones(terrain, tee_pos, cup_pos, fairway_width)

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

	# --- Step 3b: Plateau reshaping ---
	var plateau_factor: float = biome.plateau_factor if biome else 0.0
	if plateau_factor > 0.0:
		var plateau_levels: int = biome.plateau_levels if biome else 3
		_apply_plateaus(terrain, min_h, max_h, plateau_factor, plateau_levels)

	# --- Step 4: Carve fairway corridor ---
	_carve_fairway(
		terrain, spine, fairway_width, fw_flatten, ground_height,
	)

	# --- Step 5: Flatten green and tee areas ---
	var tee_flat := Vector3(tee_pos.x, 0.0, tee_pos.z)
	var cup_flat := Vector3(cup_pos.x, 0.0, cup_pos.z)
	_flatten_area(terrain, cup_flat, green_radius, ground_height)
	_flatten_area(terrain, tee_flat, tee_radius, ground_height)

	# --- Step 6: Clamp heights ---
	_clamp_heights(terrain, min_h, max_h)

	# --- Step 7: Paint hazard zones (needs final heights) ---
	if biome:
		terrain.water_height = biome.water_height
		terrain.lava_height = biome.lava_height
	_paint_hazard_zones(terrain)

	# Set key positions with correct Y
	terrain.tee_position = Vector3(
		tee_pos.x, ground_height, tee_pos.z,
	)
	terrain.cup_position = Vector3(
		cup_pos.x, ground_height, cup_pos.z,
	)

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
) -> void:
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

			if min_dist < fairway_width:
				var target_h: float = lerpf(
					spine[nearest_seg].y,
					spine[nearest_seg + 1].y,
					nearest_t,
				)
				if target_h == 0.0:
					target_h = ground_height

				var ratio: float = min_dist / fairway_width
				var blend: float = \
					flatten_strength * (1.0 - ratio * ratio)
				terrain.heights[cell_idx] = lerpf(
					terrain.heights[cell_idx], target_h, blend,
				)


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
	tee_pos: Vector3,
	cup_pos: Vector3,
	fairway_width: float,
) -> void:
	var half_fw: float = fairway_width * 0.5
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

			var dist_to_spine: float = \
				_point_to_segment_distance_xz(
					flat, tee_flat, cup_flat,
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
# Geometry helpers
# -------------------------------------------------------------------------

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
