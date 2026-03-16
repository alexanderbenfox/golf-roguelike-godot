class_name TrajectoryDrawer
extends Node3D

var line_mesh: ImmediateMesh
var mesh_instance: MeshInstance3D
var material: StandardMaterial3D

func _ready() -> void:
	create_line()
	top_level = true

func create_line() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

	line_mesh = ImmediateMesh.new()
	mesh_instance.mesh = line_mesh

	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 1.0, 0.0, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material

	hide()

func show_trajectory() -> void:
	show()

func hide_trajectory() -> void:
	hide()

func draw_arrow(start_pos: Vector3, direction: Vector3, power: float, max_power: float) -> void:
	line_mesh.clear_surfaces()

	if direction == Vector3.ZERO:
		return

	update_color(power, max_power)

	var trajectory_length: float = power * 0.5
	var end_point := direction * trajectory_length

	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	line_mesh.surface_add_vertex(start_pos)
	line_mesh.surface_add_vertex(end_point)
	line_mesh.surface_end()

	var arrow_size := 0.3
	var perpendicular := direction.cross(Vector3.UP).normalized()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	line_mesh.surface_add_vertex(end_point)
	line_mesh.surface_add_vertex(end_point - direction * arrow_size + perpendicular * arrow_size * 0.5)
	line_mesh.surface_add_vertex(end_point)
	line_mesh.surface_add_vertex(end_point - direction * arrow_size - perpendicular * arrow_size * 0.5)
	line_mesh.surface_end()

func draw_trajectory(params: PhysicsSimulator.PhysicsParams, impulse: Vector3) -> void:
	line_mesh.clear_surfaces()

	if impulse == Vector3.ZERO:
		return

	var initial_velocity: Vector3 = impulse / params.mass

	update_color_from_impulse(impulse.length())

	var positions: Array[Vector3] = PhysicsSimulator.simulate_trajectory(
		initial_velocity,
		params,
		Vector3.ZERO,
		0.05,
		10.0,
		0.1
	)

	if positions.size() > 1:
		line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for pos: Vector3 in positions:
			line_mesh.surface_add_vertex(pos)
		line_mesh.surface_end()

func draw_curved_trajectory_with_bounce(
	start_pos: Vector3,
	impulse: Vector3,
	ball_mass: float,
	bounce: float = 0.5,
	gravity_scale: float = 1.0,
	ground_height: float = 0.0
) -> void:
	line_mesh.clear_surfaces()

	if impulse == Vector3.ZERO:
		return

	var initial_velocity: Vector3 = impulse / ball_mass
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var gravity_vector := Vector3(0.0, -gravity * gravity_scale, 0.0)

	var time_step := 0.05
	var max_time := 5.0
	var num_points: int = int(max_time / time_step)

	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var current_pos: Vector3 = start_pos
	var current_velocity: Vector3 = initial_velocity
	var bounced: bool = false

	for _i: int in range(num_points):
		line_mesh.surface_add_vertex(current_pos)

		current_velocity += gravity_vector * time_step
		current_pos += current_velocity * time_step

		if current_pos.y <= ground_height and not bounced:
			current_velocity.y = -current_velocity.y * bounce
			current_velocity.x *= 0.8
			current_velocity.z *= 0.8
			current_pos.y = ground_height
			bounced = true
		elif current_pos.y <= ground_height and bounced:
			break

		if current_pos.length() > 100.0:
			break

	line_mesh.surface_end()

func interpolate_ground_hit(pos1: Vector3, pos2: Vector3, ground_height: float) -> Vector3:
	if pos2.y >= ground_height:
		return pos2

	var t: float = (ground_height - pos1.y) / (pos2.y - pos1.y)
	return pos1.lerp(pos2, t)

func update_color(power: float, max_power: float) -> void:
	var color: Color
	if power > max_power * 0.66:
		color = Color(1.0, 0.0, 0.0)
	elif power > max_power * 0.33:
		color = Color(1.0, 1.0, 0.0)
	else:
		color = Color(0.0, 1.0, 0.0)
	material.albedo_color = color

func update_color_from_impulse(impulse_magnitude: float) -> void:
	var normalized: float = clamp(impulse_magnitude / 20.0, 0.0, 1.0)

	if normalized < 0.33:
		material.albedo_color = Color(0.0, 1.0, 0.0, 0.8)
	elif normalized < 0.66:
		material.albedo_color = Color(1.0, 1.0, 0.0, 0.8)
	else:
		material.albedo_color = Color(1.0, 0.0, 0.0, 0.8)
