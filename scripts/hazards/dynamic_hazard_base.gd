## DynamicHazardBase — base class for timed hazards that cycle through
## idle → warning → active states on a fixed period.
##
## Subclasses override _on_enter_idle(), _on_enter_warning(), _on_enter_active()
## to drive visuals, and implement _build_visuals() for initial geometry.
##
## Collision can run in two modes (set via hazard_definition.collision_mode):
##   AREA:      fires when ball enters the Area3D (geysers, lightning)
##   PROXIMITY: fires when ball is near a moving collider position (rock slides)
##              Subclass overrides _get_collider_positions() to return positions.
class_name DynamicHazardBase
extends Node3D

signal hazard_activated(impulse: Vector3)
signal state_changed(hazard_name: StringName, new_state: State)

enum State { IDLE, WARNING, ACTIVE }

## Mirrors HazardDefinition.CollisionMode to avoid cross-script dependency.
const COLLISION_AREA: int = 0
const COLLISION_PROXIMITY: int = 1

var hazard_definition: Resource  # HazardDefinition
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
var _hit_bodies: Dictionary = {}


func setup(descriptor: RefCounted) -> void:
	if "hazard_definition" in descriptor and descriptor.hazard_definition:
		hazard_definition = descriptor.hazard_definition
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
		var hname: StringName = hazard_definition.hazard_name \
			if hazard_definition else &""
		match _state:
			State.IDLE:
				_collision_shape.disabled = true
				_on_enter_idle()
			State.WARNING:
				_collision_shape.disabled = true
				_on_enter_warning()
			State.ACTIVE:
				_collision_shape.disabled = false
				_hit_bodies.clear()
				_on_enter_active()
		state_changed.emit(hname, _state)

	_update_visuals(delta, _state, phase)

	if _state == State.ACTIVE and _get_collision_mode() == \
			COLLISION_PROXIMITY:
		_check_proximity()


func _on_body_entered(body: Node3D) -> void:
	if _get_collision_mode() == COLLISION_PROXIMITY:
		return
	if _state != State.ACTIVE:
		return
	_fire_impulse(body)


func _fire_impulse(body: Node3D) -> void:
	var impulse := _compute_impulse(body.global_position)
	hazard_activated.emit(impulse)


func _check_proximity() -> void:
	var hit_radius: float = 2.0
	if hazard_definition and "proximity_hit_radius" in hazard_definition:
		hit_radius = hazard_definition.proximity_hit_radius
	var collider_positions: Array[Vector3] = _get_collider_positions()
	for body: Node3D in _area.get_overlapping_bodies():
		if body.get_instance_id() in _hit_bodies:
			continue
		var body_pos: Vector3 = body.global_position
		for cpos: Vector3 in collider_positions:
			if body_pos.distance_to(cpos) < hit_radius:
				_hit_bodies[body.get_instance_id()] = true
				_fire_impulse(body)
				break


func _get_collision_mode() -> int:
	if hazard_definition:
		return hazard_definition.collision_mode
	return COLLISION_AREA


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

## Return world positions of moving colliders for PROXIMITY mode.
## Override in subclasses with moving hazard elements (e.g. boulders).
func _get_collider_positions() -> Array[Vector3]:
	return [global_position]
