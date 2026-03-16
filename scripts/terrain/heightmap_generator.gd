## HeightmapGenerator — produces a TerrainData from hole routing + noise.
##
## Pure static functions, no Godot nodes. All generation is deterministic
## from the provided RandomNumberGenerator.
##
## Pipeline: noise fill → fairway carving → green/tee flattening → zone painting.
class_name HeightmapGenerator
extends RefCounted

const TerrainDataScript = preload("res://scripts/terrain/terrain_data.gd")

# ---- Noise defaults (will come from BiomeDefinition in Phase 6) ----

const NOISE_FREQUENCY: float     = 0.012
const NOISE_OCTAVES: int         = 3
const NOISE_LACUNARITY: float    = 2.0
const NOISE_GAIN: float          = 0.5
const AMPLITUDE: float           = 3.0
const FAIRWAY_FLATTEN: float     = 0.85
const GREEN_FLATTEN_RADIUS: float = 10.0
const TEE_FLATTEN_RADIUS: float  = 5.0


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

## Generate a TerrainData for the given hole routing.
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
) -> RefCounted:
	var noise_seed: int = rng.randi()

	var terrain: RefCounted = TerrainDataScript.new()
	terrain.cell_size = cell_size

	# Compute grid bounds — axis-aligned bounding box around the rotated hole + margin.
	var dir := Vector3(sin(hole_direction), 0.0, -cos(hole_direction))
	var right := Vector3(cos(hole_direction), 0.0, sin(hole_direction))

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
	terrain.grid_width = maxi(int(ceil((max_x - min_x) / cell_size)), 2)
	terrain.grid_depth = maxi(int(ceil((max_z - min_z) / cell_size)), 2)

	var total_cells: int = terrain.grid_width * terrain.grid_depth
	terrain.heights.resize(total_cells)
	terrain.zones.resize(total_cells)

	# --- Step 1: Noise-based heightmap ---
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = NOISE_FREQUENCY
	noise.fractal_octaves = NOISE_OCTAVES
	noise.fractal_lacunarity = NOISE_LACUNARITY
	noise.fractal_gain = NOISE_GAIN

	_fill_noise(terrain, noise, ground_height, AMPLITUDE)

	# --- Step 2: Carve fairway corridor toward ground_height ---
	_carve_fairway(terrain, spine, fairway_width, FAIRWAY_FLATTEN, ground_height)

	# --- Step 3: Flatten green and tee areas ---
	var tee_flat := Vector3(tee_pos.x, 0.0, tee_pos.z)
	var cup_flat := Vector3(cup_pos.x, 0.0, cup_pos.z)
	_flatten_area(terrain, cup_flat, GREEN_FLATTEN_RADIUS, ground_height)
	_flatten_area(terrain, tee_flat, TEE_FLATTEN_RADIUS, ground_height)

	# --- Step 4: Zone painting ---
	_paint_zones(terrain, tee_pos, cup_pos, fairway_width)

	# Set key positions with correct Y
	terrain.tee_position = Vector3(tee_pos.x, ground_height, tee_pos.z)
	terrain.cup_position = Vector3(cup_pos.x, ground_height, cup_pos.z)

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
			var h: float = ground_height + noise.get_noise_2d(world.x, world.z) * amplitude
			terrain.heights[terrain._idx(gx, gz)] = h


## Blend cells near the fairway spine toward the spine's intended elevation.
## Uses quadratic falloff so the centre is flattest and edges blend into rough.
static func _carve_fairway(
	terrain: RefCounted,
	spine: Array[Vector3],
	fairway_width: float,
	flatten_strength: float,
	ground_height: float,
) -> void:
	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var idx: int = terrain._idx(gx, gz)
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var flat := Vector3(world.x, 0.0, world.z)

			# Find distance to nearest spine segment and the parameter t along it
			var min_dist: float = INF
			var nearest_t: float = 0.0
			var nearest_seg: int = 0

			for i: int in range(spine.size() - 1):
				var a := Vector3(spine[i].x, 0.0, spine[i].z)
				var b := Vector3(spine[i + 1].x, 0.0, spine[i + 1].z)
				var dist: float = _point_to_segment_distance_xz(flat, a, b)
				if dist < min_dist:
					min_dist = dist
					nearest_seg = i
					var ab := b - a
					var ap := flat - a
					var ab_len_sq: float = ab.length_squared()
					nearest_t = clampf(ap.dot(ab) / maxf(ab_len_sq, 0.001), 0.0, 1.0)

			if min_dist < fairway_width:
				# Intended height at nearest spine point
				var target_h: float = lerpf(
					spine[nearest_seg].y, spine[nearest_seg + 1].y, nearest_t
				)
				if target_h == 0.0:
					target_h = ground_height

				# Quadratic falloff: centre = full strength, edges = zero
				var ratio: float = min_dist / fairway_width
				var blend: float = flatten_strength * (1.0 - ratio * ratio)
				terrain.heights[idx] = lerpf(terrain.heights[idx], target_h, blend)


## Flatten terrain in a circular area (for green / tee).
## Quadratic falloff: centre snaps to target_height, edge blends smoothly.
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
				var idx: int = terrain._idx(gx, gz)
				terrain.heights[idx] = lerpf(terrain.heights[idx], target_height, blend)


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
	var green_radius_sq: float = 8.0 * 8.0  # GREEN_RADIUS = 8.0
	var tee_radius_sq: float = 3.0 * 3.0    # tee box ~3m radius

	var cup_flat := Vector3(cup_pos.x, 0.0, cup_pos.z)
	var tee_flat := Vector3(tee_pos.x, 0.0, tee_pos.z)

	for gz: int in range(terrain.grid_depth):
		for gx: int in range(terrain.grid_width):
			var idx: int = terrain._idx(gx, gz)
			var world: Vector3 = terrain.grid_to_world(gx, gz)
			var flat := Vector3(world.x, 0.0, world.z)

			var to_cup_sq: float = flat.distance_squared_to(cup_flat)
			var to_tee_sq: float = flat.distance_squared_to(tee_flat)

			if to_cup_sq <= green_radius_sq:
				terrain.zones[idx] = TerrainDataScript.ZoneType.GREEN
				continue

			if to_tee_sq <= tee_radius_sq:
				terrain.zones[idx] = TerrainDataScript.ZoneType.TEE
				continue

			var dist_to_spine: float = _point_to_segment_distance_xz(
				flat, tee_flat, cup_flat
			)
			if dist_to_spine <= half_fw:
				terrain.zones[idx] = TerrainDataScript.ZoneType.FAIRWAY
				continue

			terrain.zones[idx] = TerrainDataScript.ZoneType.ROUGH


# -------------------------------------------------------------------------
# Geometry helpers
# -------------------------------------------------------------------------

## Returns the XZ-plane distance from a point to a line segment.
static func _point_to_segment_distance_xz(
	point: Vector3, seg_a: Vector3, seg_b: Vector3
) -> float:
	var ab := Vector3(seg_b.x - seg_a.x, 0.0, seg_b.z - seg_a.z)
	var ap := Vector3(point.x - seg_a.x, 0.0, point.z - seg_a.z)
	var ab_len_sq: float = ab.x * ab.x + ab.z * ab.z
	if ab_len_sq < 0.001:
		return ap.length()
	var t: float = clampf((ap.x * ab.x + ap.z * ab.z) / ab_len_sq, 0.0, 1.0)
	var closest := Vector3(seg_a.x + ab.x * t, 0.0, seg_a.z + ab.z * t)
	return Vector3(point.x - closest.x, 0.0, point.z - closest.z).length()
