## HazardParticleColumn — configurable eruption / column particle effect.
##
## Used by SandGeyserHazard, LavaGeyserHazard, and similar vertical eruptions.
class_name HazardParticleColumn
extends GPUParticles3D

var _process_mat: ParticleProcessMaterial


func setup(
	radius: float,
	color: Color,
	particle_count: int = 40,
) -> void:
	amount = particle_count

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.direction = Vector3(0.0, 1.0, 0.0)
	_process_mat.spread = 12.0
	_process_mat.initial_velocity_min = 6.0
	_process_mat.initial_velocity_max = 10.0
	_process_mat.gravity = Vector3(0.0, -4.0, 0.0)
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_process_mat.emission_sphere_radius = radius * 0.4
	_process_mat.scale_min = 0.6
	_process_mat.scale_max = 1.2

	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.1, 0.8))
	curve.add_point(Vector2(0.6, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	_process_mat.alpha_curve = alpha_curve
	process_material = _process_mat

	var draw_mesh := QuadMesh.new()
	draw_mesh.size = Vector2(0.3, 0.3)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = color
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mesh.material = draw_mat
	draw_pass_1 = draw_mesh

	lifetime = 1.5
	emitting = false
	visibility_aabb = AABB(
		Vector3(-radius, -1, -radius),
		Vector3(radius * 2, 12, radius * 2),
	)


## Scale particle velocity to control eruption intensity.
## (0, 0) = off. (2, 4) = light wisps. (6, 10) = full eruption.
func set_eruption_strength(min_vel: float, max_vel: float) -> void:
	_process_mat.initial_velocity_min = min_vel
	_process_mat.initial_velocity_max = max_vel


func start(particle_count: int = -1) -> void:
	if particle_count > 0:
		amount = particle_count
	emitting = true


func stop() -> void:
	emitting = false
