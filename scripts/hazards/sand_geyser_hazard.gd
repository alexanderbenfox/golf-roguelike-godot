## SandGeyserHazard — desert geyser that erupts on a timer, launching
## nearby balls upward.
##
## Visual states:
##   IDLE:    darkened sand disc + faint steam wisps
##   WARNING: disc pulses, sand particles begin rising
##   ACTIVE:  full sand column eruption, Area3D enabled
class_name SandGeyserHazard
extends DynamicHazardBase

var _ground_disc: MeshInstance3D
var _particles: GPUParticles3D
var _disc_material: StandardMaterial3D
var _warning_time: float = 0.0


func _build_visuals() -> void:
	# Ground disc — darkened sand patch
	_ground_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = effect_radius
	disc.bottom_radius = effect_radius
	disc.height = 0.05
	_ground_disc.mesh = disc

	_disc_material = StandardMaterial3D.new()
	_disc_material.albedo_color = Color(0.6, 0.45, 0.25, 0.7)
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ground_disc.material_override = _disc_material
	_ground_disc.position.y = 0.03
	add_child(_ground_disc)

	# Eruption particles
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 12.0
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 10.0
	mat.gravity = Vector3(0.0, -4.0, 0.0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = effect_radius * 0.4
	mat.scale_min = 0.6
	mat.scale_max = 1.2

	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.1, 0.8))
	curve.add_point(Vector2(0.6, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve

	var draw_mesh := QuadMesh.new()
	draw_mesh.size = Vector2(0.3, 0.3)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = Color(0.85, 0.70, 0.40, 0.6)
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mesh.material = draw_mat

	_particles = GPUParticles3D.new()
	_particles.process_material = mat
	_particles.draw_pass_1 = draw_mesh
	_particles.amount = 40
	_particles.lifetime = 1.5
	_particles.emitting = false
	_particles.visibility_aabb = AABB(
		Vector3(-effect_radius, -1, -effect_radius),
		Vector3(effect_radius * 2, 12, effect_radius * 2),
	)
	add_child(_particles)


func _on_enter_idle() -> void:
	_disc_material.albedo_color = Color(0.6, 0.45, 0.25, 0.7)
	_particles.emitting = false
	_warning_time = 0.0


func _on_enter_warning() -> void:
	_warning_time = 0.0
	# Start with a few particles rising
	_particles.amount = 12
	_particles.emitting = true
	var mat: ParticleProcessMaterial = _particles.process_material
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0


func _on_enter_active() -> void:
	# Full eruption
	_particles.amount = 40
	var mat: ParticleProcessMaterial = _particles.process_material
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 10.0
	_disc_material.albedo_color = Color(0.85, 0.60, 0.25, 0.9)


func _update_visuals(delta: float, current_state: State, _phase: float) -> void:
	if current_state == State.WARNING:
		# Pulse the disc
		_warning_time += delta
		var pulse: float = 0.5 + 0.5 * sin(_warning_time * 6.0)
		_disc_material.albedo_color = Color(
			lerpf(0.6, 0.85, pulse),
			lerpf(0.45, 0.55, pulse),
			0.25,
			lerpf(0.7, 0.9, pulse),
		)


func _compute_impulse(ball_pos: Vector3) -> Vector3:
	# Launch upward + slightly away from center
	var away := ball_pos - global_position
	away.y = 0.0
	if away.length_squared() > 0.01:
		away = away.normalized()
	else:
		away = Vector3.FORWARD
	return Vector3.UP * intensity + away * intensity * 0.3
