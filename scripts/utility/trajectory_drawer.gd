## TrajectoryDrawer — renders a flat arrow ribbon, landing halo, and accuracy
## variance cone using ImmediateMesh.
class_name TrajectoryDrawer
extends Node3D

const ARROW_HALF_WIDTH: float = 0.25
const ARROW_HEAD_HALF_WIDTH: float = 0.55
const HALO_INNER_RADIUS: float = 1.0
const HALO_OUTER_RADIUS: float = 1.4
const HALO_SEGMENTS: int = 32
const MAX_SPREAD_RADIANS: float = 0.10
const VARIANCE_ARC_SEGMENTS: int = 16
const GROUND_RIBBON_OFFSET: float = 0.02

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _arrow_material: StandardMaterial3D
var _halo_material: StandardMaterial3D
var _variance_material: StandardMaterial3D

# Stored during draw_trajectory so helpers can query terrain height.
var _terrain: RefCounted = null
var _flat_ground_height: float = 0.5


func _ready() -> void:
	_setup_materials()
	_setup_mesh()
	top_level = true


func _setup_materials() -> void:
	_arrow_material = StandardMaterial3D.new()
	_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_material.albedo_color = Color(1.0, 1.0, 0.0, 0.8)
	_arrow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arrow_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_halo_material = StandardMaterial3D.new()
	_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_material.albedo_color = Color(1.0, 1.0, 1.0, 0.45)
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_variance_material = StandardMaterial3D.new()
	_variance_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_variance_material.albedo_color = Color(1.0, 1.0, 0.0, 0.2)
	_variance_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_variance_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _setup_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh
	hide()


func show_trajectory() -> void:
	show()


func hide_trajectory() -> void:
	hide()


# -------------------------------------------------------------------------
# Main entry point — called every frame while aiming
# -------------------------------------------------------------------------

func draw_trajectory(
	params: PhysicsSimulator.PhysicsParams,
	impulse: Vector3,
	accuracy: float = 1.0,
	start_pos: Vector3 = Vector3.ZERO,
) -> void:
	_mesh.clear_surfaces()

	if impulse.length_squared() < 0.001:
		return

	# Cache terrain for helpers
	_terrain = params.terrain
	_flat_ground_height = params.ground_height

	var initial_velocity: Vector3 = impulse / params.mass
	_update_arrow_color(impulse.length())

	var positions: Array[Vector3] = PhysicsSimulator.simulate_trajectory(
		initial_velocity, params, start_pos, 0.05, 10.0, 0.1
	)

	if positions.size() < 2:
		return

	var landing_pos: Vector3 = _find_landing_point(positions)

	_draw_ribbon(positions)
	_draw_halo(landing_pos)

	# Draw accuracy variance cone if not perfectly accurate
	var spread: float = (1.0 - clampf(accuracy, 0.0, 1.0)) * MAX_SPREAD_RADIANS
	if spread > 0.001:
		_draw_variance_cone(impulse, params, spread, start_pos)


# -------------------------------------------------------------------------
# Terrain-aware ground height helpers
# -------------------------------------------------------------------------

## Returns the terrain surface Y at a world XZ, plus a small ribbon offset.
func _ribbon_y_at(world_x: float, world_z: float) -> float:
	if _terrain:
		return _terrain.get_height_at(world_x, world_z) + GROUND_RIBBON_OFFSET
	return _flat_ground_height + GROUND_RIBBON_OFFSET


## Returns the raw terrain surface Y at a world XZ (no offset).
func _surface_y_at(world_x: float, world_z: float) -> float:
	if _terrain:
		return _terrain.get_height_at(world_x, world_z)
	return _flat_ground_height


# -------------------------------------------------------------------------
# Landing point detection
# -------------------------------------------------------------------------

func _find_landing_point(positions: Array[Vector3]) -> Vector3:
	for i: int in range(1, positions.size()):
		var ground_y: float = _surface_y_at(positions[i].x, positions[i].z)
		if positions[i].y <= ground_y + 0.1:
			var dy: float = positions[i].y - positions[i - 1].y
			if absf(dy) > 0.001:
				var t: float = clampf((ground_y - positions[i - 1].y) / dy, 0.0, 1.0)
				return positions[i - 1].lerp(positions[i], t)
			return positions[i]
	return positions[positions.size() - 1]


# -------------------------------------------------------------------------
# Flat arrow ribbon (triangle strip) with arrowhead
# -------------------------------------------------------------------------

func _draw_ribbon(positions: Array[Vector3]) -> void:
	var count: int = positions.size()
	if count < 2:
		return

	# Reserve last 2 points for arrowhead base/tip
	var ribbon_end: int = maxi(count - 2, 2)

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _arrow_material)

	for i: int in range(ribbon_end):
		var pos: Vector3 = positions[i]
		var forward: Vector3
		if i < ribbon_end - 1:
			forward = (positions[i + 1] - pos).normalized()
		else:
			forward = (pos - positions[i - 1]).normalized()

		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		if right.length_squared() < 0.01:
			right = Vector3.RIGHT

		# Slight taper toward the tip
		var t: float = float(i) / float(maxi(ribbon_end - 1, 1))
		var half_w: float = ARROW_HALF_WIDTH * lerpf(1.0, 0.6, t)

		var left_v: Vector3 = pos + right * half_w
		var right_v: Vector3 = pos - right * half_w
		var min_y: float = _ribbon_y_at(pos.x, pos.z)
		left_v.y = maxf(left_v.y, min_y)
		right_v.y = maxf(right_v.y, min_y)

		_mesh.surface_add_vertex(left_v)
		_mesh.surface_add_vertex(right_v)

	_mesh.surface_end()

	# Arrowhead triangle
	if count >= 3:
		var tip: Vector3 = positions[count - 1]
		var base_idx: int = mini(ribbon_end, count - 2)
		var base: Vector3 = positions[base_idx]
		var fwd: Vector3 = (tip - base).normalized()
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		if right.length_squared() < 0.01:
			right = Vector3.RIGHT

		var tip_min_y: float = _ribbon_y_at(tip.x, tip.z)
		tip.y = maxf(tip.y, tip_min_y)
		var left_wing: Vector3 = base + right * ARROW_HEAD_HALF_WIDTH
		var right_wing: Vector3 = base - right * ARROW_HEAD_HALF_WIDTH
		var base_min_y: float = _ribbon_y_at(base.x, base.z)
		left_wing.y = maxf(left_wing.y, base_min_y)
		right_wing.y = maxf(right_wing.y, base_min_y)

		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _arrow_material)
		_mesh.surface_add_vertex(left_wing)
		_mesh.surface_add_vertex(tip)
		_mesh.surface_add_vertex(right_wing)
		_mesh.surface_end()


# -------------------------------------------------------------------------
# Landing halo — ring at the first ground-hit point
# -------------------------------------------------------------------------

func _draw_halo(center: Vector3) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _halo_material)

	for i: int in range(HALO_SEGMENTS + 1):
		var angle: float = float(i) / float(HALO_SEGMENTS) * TAU
		var ca: float = cos(angle)
		var sa: float = sin(angle)

		var outer_x: float = center.x + ca * HALO_OUTER_RADIUS
		var outer_z: float = center.z + sa * HALO_OUTER_RADIUS
		var inner_x: float = center.x + ca * HALO_INNER_RADIUS
		var inner_z: float = center.z + sa * HALO_INNER_RADIUS

		_mesh.surface_add_vertex(Vector3(
			outer_x, _surface_y_at(outer_x, outer_z) + 0.03, outer_z
		))
		_mesh.surface_add_vertex(Vector3(
			inner_x, _surface_y_at(inner_x, inner_z) + 0.03, inner_z
		))

	_mesh.surface_end()


# -------------------------------------------------------------------------
# Accuracy variance — edge trajectories and landing arc
# -------------------------------------------------------------------------

func _draw_variance_cone(
	impulse: Vector3,
	params: PhysicsSimulator.PhysicsParams,
	spread: float,
	start_pos: Vector3 = Vector3.ZERO,
) -> void:
	var left_impulse: Vector3 = impulse.rotated(Vector3.UP, spread)
	var right_impulse: Vector3 = impulse.rotated(Vector3.UP, -spread)

	var left_vel: Vector3 = left_impulse / params.mass
	var right_vel: Vector3 = right_impulse / params.mass

	var left_pos: Array[Vector3] = PhysicsSimulator.simulate_trajectory(
		left_vel, params, start_pos, 0.05, 10.0, 0.1
	)
	var right_pos: Array[Vector3] = PhysicsSimulator.simulate_trajectory(
		right_vel, params, start_pos, 0.05, 10.0, 0.1
	)

	# Left edge line
	if left_pos.size() > 1:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _variance_material)
		for pos: Vector3 in left_pos:
			var min_y: float = _ribbon_y_at(pos.x, pos.z)
			_mesh.surface_add_vertex(Vector3(pos.x, maxf(pos.y, min_y), pos.z))
		_mesh.surface_end()

	# Right edge line
	if right_pos.size() > 1:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _variance_material)
		for pos: Vector3 in right_pos:
			var min_y: float = _ribbon_y_at(pos.x, pos.z)
			_mesh.surface_add_vertex(Vector3(pos.x, maxf(pos.y, min_y), pos.z))
		_mesh.surface_end()

	# Arc connecting the two landing points
	var left_landing: Vector3 = _find_landing_point(left_pos)
	var right_landing: Vector3 = _find_landing_point(right_pos)

	if left_landing.distance_to(right_landing) > 0.1:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _variance_material)
		for i: int in range(VARIANCE_ARC_SEGMENTS + 1):
			var t: float = float(i) / float(VARIANCE_ARC_SEGMENTS)
			var p: Vector3 = left_landing.lerp(right_landing, t)
			p.y = _surface_y_at(p.x, p.z) + 0.03
			_mesh.surface_add_vertex(p)
		_mesh.surface_end()


# -------------------------------------------------------------------------
# Color helpers
# -------------------------------------------------------------------------

func _update_arrow_color(impulse_magnitude: float) -> void:
	var normalized: float = clampf(impulse_magnitude / 20.0, 0.0, 1.0)
	if normalized < 0.33:
		_arrow_material.albedo_color = Color(0.0, 1.0, 0.0, 0.8)
	elif normalized < 0.66:
		_arrow_material.albedo_color = Color(1.0, 1.0, 0.0, 0.8)
	else:
		_arrow_material.albedo_color = Color(1.0, 0.0, 0.0, 0.8)
