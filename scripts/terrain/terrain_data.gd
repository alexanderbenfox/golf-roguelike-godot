## TerrainData — grid-based heightmap + zone map for a single hole.
##
## Generated once by HeightmapGenerator, then queried at runtime by
## PhysicsSimulator, TrajectoryDrawer, and ProceduralHole.
##
## Heights are stored in a flat PackedFloat32Array (row-major, grid_width * grid_depth).
## Zones are stored in a PackedByteArray with the same layout.
## Both support fast bilinear / nearest-cell lookups via world-space coordinates.
class_name TerrainData
extends RefCounted

# ---- Zone types ------------------------------------------------------------

enum ZoneType {
	FAIRWAY = 0,
	ROUGH = 1,
	GREEN = 2,
	TEE = 3,
	BUNKER = 4,
	WATER = 5,
	LAVA = 6,
	OOB = 7,
}

# ---- Grid storage ----------------------------------------------------------

## Number of cells along the X axis.
var grid_width: int = 0
## Number of cells along the Z axis.
var grid_depth: int = 0
## World-space size of each cell (e.g. 2.0 means 2m per cell).
var cell_size: float = 2.0
## World-space position of the grid corner at index (0, 0).
var origin: Vector3 = Vector3.ZERO

## Flat height array — grid_width * grid_depth entries, row-major (x + z * grid_width).
var heights: PackedFloat32Array = PackedFloat32Array()
## Flat zone array — same layout as heights, stores ZoneType as bytes.
var zones: PackedByteArray = PackedByteArray()

# ---- Key positions (world-space, with correct Y from heightmap) ------------

var tee_position: Vector3 = Vector3.ZERO
var cup_position: Vector3 = Vector3.ZERO
## Control points describing the fairway centre line from tee to cup.
var fairway_spine: Array[Vector3] = []

# ---- Hazard planes ---------------------------------------------------------

## Height below which terrain is submerged. Set to -999.0 to disable water.
var water_height: float = -999.0
## Height below which terrain is lava. Set to -999.0 to disable lava.
var lava_height: float = -999.0

# ---- Friction modifiers per zone (set by biome) ---------------------------

var fairway_friction: float = 1.0
var rough_friction: float = 1.5
var green_friction: float = 0.7
var bunker_friction: float = 3.0


# -------------------------------------------------------------------------
# Grid helpers
# -------------------------------------------------------------------------

## Convert world XZ to grid indices (clamped to valid range).
func world_to_grid(world_x: float, world_z: float) -> Vector2i:
	var gx: int = clampi(
		int((world_x - origin.x) / cell_size), 0, grid_width - 1
	)
	var gz: int = clampi(
		int((world_z - origin.z) / cell_size), 0, grid_depth - 1
	)
	return Vector2i(gx, gz)


## Convert grid indices to world-space position (cell centre, Y from heightmap).
func grid_to_world(gx: int, gz: int) -> Vector3:
	var wx: float = origin.x + (float(gx) + 0.5) * cell_size
	var wz: float = origin.z + (float(gz) + 0.5) * cell_size
	var wy: float = _get_height_raw(gx, gz)
	return Vector3(wx, wy, wz)


## Flat index into heights / zones arrays.
func _idx(gx: int, gz: int) -> int:
	return gx + gz * grid_width


## Raw height at integer grid coords (clamped).
func _get_height_raw(gx: int, gz: int) -> float:
	gx = clampi(gx, 0, grid_width - 1)
	gz = clampi(gz, 0, grid_depth - 1)
	return heights[_idx(gx, gz)]


# -------------------------------------------------------------------------
# Public query API
# -------------------------------------------------------------------------

## Returns the interpolated terrain height at a world XZ position.
## Uses bilinear interpolation between the four nearest grid cells.
func get_height_at(world_x: float, world_z: float) -> float:
	var fx: float = (world_x - origin.x) / cell_size - 0.5
	var fz: float = (world_z - origin.z) / cell_size - 0.5

	var x0: int = clampi(int(fx), 0, grid_width - 2)
	var z0: int = clampi(int(fz), 0, grid_depth - 2)
	var x1: int = x0 + 1
	var z1: int = z0 + 1

	var tx: float = clampf(fx - float(x0), 0.0, 1.0)
	var tz: float = clampf(fz - float(z0), 0.0, 1.0)

	var h00: float = heights[_idx(x0, z0)]
	var h10: float = heights[_idx(x1, z0)]
	var h01: float = heights[_idx(x0, z1)]
	var h11: float = heights[_idx(x1, z1)]

	var h0: float = lerpf(h00, h10, tx)
	var h1: float = lerpf(h01, h11, tx)
	return lerpf(h0, h1, tz)


## Returns the surface normal at a world XZ position.
## Computed from the height gradient of neighbouring samples.
func get_normal_at(world_x: float, world_z: float) -> Vector3:
	var eps: float = cell_size
	var hL: float = get_height_at(world_x - eps, world_z)
	var hR: float = get_height_at(world_x + eps, world_z)
	var hD: float = get_height_at(world_x, world_z - eps)
	var hU: float = get_height_at(world_x, world_z + eps)

	# Tangent vectors along X and Z, cross product gives normal
	var normal := Vector3(hL - hR, 2.0 * eps, hD - hU).normalized()
	return normal


## Returns the zone type at a world XZ position (nearest cell).
func get_zone_at(world_x: float, world_z: float) -> ZoneType:
	var g: Vector2i = world_to_grid(world_x, world_z)
	return zones[_idx(g.x, g.y)] as ZoneType


## Returns the friction modifier for the zone at a world XZ position.
func get_friction_at(world_x: float, world_z: float) -> float:
	var zone: ZoneType = get_zone_at(world_x, world_z)
	match zone:
		ZoneType.FAIRWAY:
			return fairway_friction
		ZoneType.GREEN:
			return green_friction
		ZoneType.ROUGH:
			return rough_friction
		ZoneType.BUNKER:
			return bunker_friction
		ZoneType.WATER, ZoneType.LAVA:
			return rough_friction
		_:
			return rough_friction


## Returns true if the position is in a water hazard.
func is_water_at(world_x: float, world_z: float) -> bool:
	return water_height > -900.0 and get_height_at(world_x, world_z) < water_height


## Returns true if the position is in a lava hazard.
func is_lava_at(world_x: float, world_z: float) -> bool:
	return lava_height > -900.0 and get_height_at(world_x, world_z) < lava_height
