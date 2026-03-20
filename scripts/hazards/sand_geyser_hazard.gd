## SandGeyserHazard — desert geyser that erupts on a timer, launching
## nearby balls upward.
##
## Visual states:
##   IDLE:    darkened sand disc + faint steam wisps
##   WARNING: disc pulses, sand particles begin rising
##   ACTIVE:  full sand column eruption, Area3D enabled
class_name SandGeyserHazard
extends DynamicHazardBase

var _disc: HazardWarningDisc
var _column: HazardParticleColumn
var _warning_time: float = 0.0


func _build_visuals() -> void:
	# Ground disc — darkened sand patch
	_disc = HazardWarningDisc.new()
	_disc.setup(
		effect_radius,
		Color(0.6, 0.45, 0.25, 0.7),
		Color(0.85, 0.60, 0.25, 0.9),
	)
	add_child(_disc)

	# Eruption particles
	_column = HazardParticleColumn.new()
	_column.setup(
		effect_radius,
		Color(0.85, 0.70, 0.40, 0.6),
		40,
	)
	add_child(_column)


func _on_enter_idle() -> void:
	_disc.set_state(0)
	_column.stop()
	_warning_time = 0.0


func _on_enter_warning() -> void:
	_warning_time = 0.0
	_column.set_eruption_strength(2.0, 4.0)
	_column.start(12)


func _on_enter_active() -> void:
	_column.set_eruption_strength(6.0, 10.0)
	_column.start(40)
	_disc.set_state(2)


func _update_visuals(
	delta: float, current_state: State, _phase: float,
) -> void:
	if current_state == State.WARNING:
		_warning_time += delta
		_disc.set_state(1, _warning_time)


func _compute_impulse(ball_pos: Vector3) -> Vector3:
	# Launch upward + slightly away from center
	var away := ball_pos - global_position
	away.y = 0.0
	if away.length_squared() > 0.01:
		away = away.normalized()
	else:
		away = Vector3.FORWARD
	return Vector3.UP * intensity + away * intensity * 0.3
