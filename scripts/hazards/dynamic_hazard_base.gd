## DynamicHazardBase — base class for timed hazards that cycle through
## idle → warning → active states on a fixed period.
##
## Subclasses override _on_enter_idle(), _on_enter_warning(), _on_enter_active()
## to drive visuals, and implement _build_visuals() for initial geometry.
##
## The Area3D collision shape is only enabled during the ACTIVE state.
## When a ball enters the active zone, hazard_activated is emitted with
## an impulse vector for the ball to apply.
class_name DynamicHazardBase
extends Node3D

signal hazard_activated(impulse: Vector3)

enum State { IDLE, WARNING, ACTIVE }

var hazard_type: int  # DynamicHazardDescriptor.HazardType
var effect_radius: float
var cycle_period: float
var active_duration: float
var warning_duration: float
var phase_offset: float
var intensity: float
var slide_direction: Vector3

var _state: State = State.IDLE
var _elapsed: float = 0.0
var _area: Area3D
var _collision_shape: CollisionShape3D


func setup(descriptor: RefCounted) -> void:
	hazard_type = descriptor.type
	effect_radius = descriptor.effect_radius
	cycle_period = descriptor.cycle_period
	active_duration = descriptor.active_duration
	warning_duration = descriptor.warning_duration
	phase_offset = descriptor.phase_offset
	intensity = descriptor.intensity
	slide_direction = descriptor.direction


func _ready() -> void:
	# Area3D for ball detection
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1  # detect ball layer
	_area.monitoring = true
	_area.monitorable = false

	var shape := CylinderShape3D.new()
	shape.radius = effect_radius
	shape.height = 6.0
	_collision_shape = CollisionShape3D.new()
	_collision_shape.shape = shape
	_collision_shape.disabled = true  # only enabled during ACTIVE
	_area.add_child(_collision_shape)
	add_child(_area)

	_area.body_entered.connect(_on_body_entered)

	_build_visuals()
	_on_enter_idle()


func _process(delta: float) -> void:
	_elapsed += delta
	var phase: float = fmod(_elapsed + phase_offset, cycle_period)

	var idle_duration: float = cycle_period - active_duration - warning_duration
	var new_state: State
	if phase < idle_duration:
		new_state = State.IDLE
	elif phase < idle_duration + warning_duration:
		new_state = State.WARNING
	else:
		new_state = State.ACTIVE

	if new_state != _state:
		_state = new_state
		match _state:
			State.IDLE:
				_collision_shape.disabled = true
				_on_enter_idle()
			State.WARNING:
				_collision_shape.disabled = true
				_on_enter_warning()
			State.ACTIVE:
				_collision_shape.disabled = false
				_on_enter_active()

	_update_visuals(delta, _state, phase)


func _on_body_entered(body: Node3D) -> void:
	if _state != State.ACTIVE:
		return
	var impulse := _compute_impulse(body.global_position)
	hazard_activated.emit(impulse)


# ---- Subclass overrides ----

## Build initial visual geometry. Called once in _ready().
func _build_visuals() -> void:
	pass

## Called when entering idle state.
func _on_enter_idle() -> void:
	pass

## Called when entering warning state.
func _on_enter_warning() -> void:
	pass

## Called when entering active state.
func _on_enter_active() -> void:
	pass

## Called every frame with current state and cycle phase. Drive animations here.
func _update_visuals(_delta: float, _current_state: State, _phase: float) -> void:
	pass

## Compute the impulse to apply to a ball at the given position.
func _compute_impulse(_ball_pos: Vector3) -> Vector3:
	return Vector3.ZERO
