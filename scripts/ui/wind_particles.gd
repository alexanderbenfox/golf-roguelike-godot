## WindParticles — drifting particle effect that visualises wind direction and strength.
##
## Spawns semi-transparent particles that drift across the view in the wind
## direction. Particle count and speed scale with wind magnitude. Attaches
## itself near the camera each frame so particles are always visible.
##
## Usage: add as child of the scene root, call update_wind() each hole,
## and set camera_target to the active Camera3D.
class_name WindParticles
extends Node3D

## The camera to follow. Particles are repositioned around the camera each frame.
var camera_target: Camera3D

var _particles: GPUParticles3D
var _material: ParticleProcessMaterial
var _mesh: QuadMesh
var _wind: Vector3 = Vector3.ZERO
var _base_amount: int = 60


func _ready() -> void:
	_material = ParticleProcessMaterial.new()
	_material.direction = Vector3(1.0, -0.1, 0.0)
	_material.spread = 15.0
	_material.initial_velocity_min = 2.0
	_material.initial_velocity_max = 4.0
	_material.gravity = Vector3(0.0, -0.3, 0.0)
	_material.damping_min = 0.5
	_material.damping_max = 1.0

	# Emission box — large enough to surround the camera view
	_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_material.emission_box_extents = Vector3(20.0, 8.0, 20.0)

	# Fade out over lifetime
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 0.6))
	curve.add_point(Vector2(0.7, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	_material.alpha_curve = alpha_curve

	# Small scale with slight variation
	var scale_curve := CurveTexture.new()
	var s_curve := Curve.new()
	s_curve.add_point(Vector2(0.0, 0.8))
	s_curve.add_point(Vector2(0.5, 1.0))
	s_curve.add_point(Vector2(1.0, 0.6))
	scale_curve.curve = s_curve
	_material.scale_curve = scale_curve

	# Particle mesh — small quad
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(0.08, 0.08)

	# Particle draw pass material — unshaded, semi-transparent white
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.no_depth_test = true
	_mesh.material = draw_mat

	_particles = GPUParticles3D.new()
	_particles.process_material = _material
	_particles.draw_pass_1 = _mesh
	_particles.amount = _base_amount
	_particles.lifetime = 4.0
	_particles.visibility_aabb = AABB(Vector3(-25, -10, -25), Vector3(50, 20, 50))
	_particles.emitting = false
	add_child(_particles)


func update_wind(wind: Vector3) -> void:
	_wind = wind
	var speed: float = Vector2(wind.x, wind.z).length()

	if speed < 0.1:
		_particles.emitting = false
		return

	_particles.emitting = true

	# Direction from wind vector — normalize to unit direction
	var dir := wind.normalized()
	_material.direction = Vector3(dir.x, -0.05, dir.z)

	# Speed scales with wind magnitude
	_material.initial_velocity_min = speed * 1.5
	_material.initial_velocity_max = speed * 2.5

	# More particles for stronger wind
	var amount := int(clampf(speed * 15.0, 20, 120))
	if amount != _particles.amount:
		_particles.amount = amount

	# Spread tightens with stronger wind (more directional)
	_material.spread = clampf(25.0 - speed * 2.0, 5.0, 25.0)


func _process(_delta: float) -> void:
	if not camera_target or not _particles.emitting:
		return
	# Keep particle emitter centered on camera
	global_position = camera_target.global_position
