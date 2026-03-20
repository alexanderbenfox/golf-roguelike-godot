## RockSlideHazard — canyon hazard where boulders periodically roll
## across the fairway perpendicular to the hole direction.
##
## Visual states:
##   IDLE:    orange warning disc on the ground marking the slide path
##   WARNING: disc pulses, dust particles start at the origin side
##   ACTIVE:  boulders animate across the fairway, Area3D enabled
class_name RockSlideHazard
extends DynamicHazardBase

const BOULDER_COUNT: int = 3
const SLIDE_DISTANCE: float = 30.0

var _disc: HazardWarningDisc
var _projectiles: HazardProjectileGroup
var _warning_time: float = 0.0
var _active_time: float = 0.0


func _build_visuals() -> void:
	# Ground warning strip — elongated box along the slide path
	_disc = HazardWarningDisc.new()
	_disc.setup(
		0.0,
		Color(0.8, 0.45, 0.15, 0.5),
		Color(0.9, 0.35, 0.10, 0.7),
		Vector2(effect_radius * 2.0, 3.0),
	)
	# Orient the strip along the slide direction
	if slide_direction.length_squared() > 0.01:
		_disc.look_at_from_position(
			Vector3.ZERO,
			slide_direction,
			Vector3.UP,
		)
	_disc.position.y = 0.03
	add_child(_disc)

	# Boulder projectiles
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.35, 0.25)

	# Create varying-size boulder meshes via the group
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.6

	_projectiles = HazardProjectileGroup.new()
	_projectiles.setup(
		sphere, rock_mat,
		BOULDER_COUNT,
		0.15,   # speed_variance
		0.3,    # stagger
		SLIDE_DISTANCE,
		0.2,    # bob_amplitude
		4.0,    # spin_speed
	)
	add_child(_projectiles)


func _on_enter_idle() -> void:
	_disc.set_state(0)
	_warning_time = 0.0
	_active_time = 0.0
	_projectiles.hide_projectiles()


func _on_enter_warning() -> void:
	_warning_time = 0.0
	_projectiles.hide_projectiles()


func _on_enter_active() -> void:
	_active_time = 0.0
	_disc.set_state(2)
	_projectiles.show_projectiles()


func _update_visuals(
	delta: float, current_state: State, _phase: float,
) -> void:
	if current_state == State.WARNING:
		_warning_time += delta
		_disc.set_state(1, _warning_time)
	elif current_state == State.ACTIVE:
		_active_time += delta
		_projectiles.animate(
			_active_time, active_duration, slide_direction, delta,
		)


## Return boulder world positions for PROXIMITY collision in the base class.
func _get_collider_positions() -> Array[Vector3]:
	return _projectiles.get_projectile_positions()


func _compute_impulse(_ball_pos: Vector3) -> Vector3:
	# Knock ball in the slide direction + upward
	return slide_direction * intensity + Vector3.UP * intensity * 0.5
