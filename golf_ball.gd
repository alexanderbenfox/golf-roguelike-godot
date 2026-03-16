## GolfBall — visual + physics node for a single player's ball.
##
## Responsibilities (this script):
##   - Drive the visual ball position from PhysicsSimulator.
##   - Handle LOCAL player input when it is this player's turn.
##   - Emit signals upward; never call ScoringManager or NetworkManager directly.
##
## Signal flow for a shot:
##   [spacebar hold] → shot_ready(direction, power) emitted
##   → Main/NetworkManager routes to server → server broadcasts
##   → play_shot(direction, power) called here (and on all remote balls)
##   → simulation runs → ball_at_rest(peer_id) emitted

extends RigidBody3D

# ---- Signals ---------------------------------------------------------------

## Emitted when the local player releases the shot. Parent routes to network.
signal shot_ready(direction: Vector3, power: float)

## Emitted when the ball comes to rest after a shot.
signal ball_at_rest(peer_id: int)

## Emitted each frame while simulating, so cup detection can poll position.
signal ball_moved(position: Vector3)

## Emitted when the ball goes out of bounds and is teleported back.
signal out_of_bounds(peer_id: int)

# ---- Identity --------------------------------------------------------------

## Set by the scene that owns this ball so signals carry the right peer_id.
var peer_id: int = 1

## True when this ball belongs to the local player (shows input UI, reads input).
var is_local_player: bool = true

# ---- Aiming state ----------------------------------------------------------

var is_aiming: bool = false
var aim_direction: Vector3 = Vector3.ZERO
var aim_power: float = 0.0

@export var s_max_power: float = 10.0
@export var s_charge_rate: float = 1.0

# ---- Simulation state ------------------------------------------------------

var is_simulating: bool = false
var sim_state: PhysicsSimulator.SimulationState
var sim_params: PhysicsSimulator.PhysicsParams
var _power_multiplier: float = 1.0
var _accuracy: float = 0.7
var last_shot_position: Vector3 = Vector3.ZERO
var _bounds_check: Callable

const STOP_VELOCITY_THRESHOLD: float = 0.3

# ---- Node references (set via @export so scene wiring is explicit) ---------

@export var power_meter_ui: ProgressBar
@export var floor_node: StaticBody3D

@onready var trajectory_drawer: TrajectoryDrawer
@onready var camera: Camera3D = get_viewport().get_camera_3d()

# ---- Whether this ball is allowed to accept input this frame ---------------
# Set by TurnManager via set_turn_active().
var _turn_active: bool = false


# -------------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------------

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	add_to_group("ball")

	trajectory_drawer = TrajectoryDrawer.new()
	add_child(trajectory_drawer)

	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	setup_physics_params()


# -------------------------------------------------------------------------
# Physics params — built from the Godot node properties + optional modifiers
# -------------------------------------------------------------------------

func setup_physics_params(player: PlayerState = null) -> void:
	sim_params = PhysicsSimulator.PhysicsParams.new()
	sim_params.mass = mass
	sim_params.linear_damp = linear_damp
	sim_params.angular_damp = angular_damp
	sim_params.gravity_scale = gravity_scale
	# Floor box is centered at y=0 with height=1, so top face is at y=0.5
	sim_params.ground_height = 0.5

	for child: Node in get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is SphereShape3D:
			sim_params.ball_radius = (child as CollisionShape3D).shape.radius
			break

	if physics_material_override:
		sim_params.ball_friction = physics_material_override.friction
		sim_params.ball_bounce = physics_material_override.bounce

	if floor_node and floor_node.physics_material_override:
		sim_params.ground_friction = floor_node.physics_material_override.friction
		sim_params.ground_bounce = floor_node.physics_material_override.bounce

	# Apply roguelike modifiers if a PlayerState is provided
	if player:
		sim_params.ball_bounce *= player.bounce_modifier
		sim_params.ground_friction *= player.friction_modifier
		sim_params.gravity_scale *= player.gravity_scale
		_power_multiplier = player.power_multiplier
		_accuracy = player.accuracy


# -------------------------------------------------------------------------
# Turn control — called by TurnManager / Main
# -------------------------------------------------------------------------

## Assign a Callable(pos: Vector3) -> bool that returns true when out of bounds.
func set_bounds_check(check: Callable) -> void:
	_bounds_check = check


func set_turn_active(active: bool) -> void:
	_turn_active = active
	if not active:
		_cancel_aim()


# -------------------------------------------------------------------------
# Input & aiming — only runs when is_local_player and _turn_active
# -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if is_local_player and _turn_active and is_at_rest() and not is_aiming:
		if Input.is_action_just_pressed("golf_shoot"):
			_start_aiming()

	if is_aiming:
		_update_aim(delta)
		trajectory_drawer.global_position = global_position
		trajectory_drawer.draw_trajectory(
			sim_params, aim_direction * aim_power * _power_multiplier, _accuracy
		)

		if Input.is_action_just_released("golf_shoot"):
			_confirm_shot()


func _start_aiming() -> void:
	is_aiming = true
	aim_power = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if power_meter_ui:
		power_meter_ui.show_meter()
	trajectory_drawer.show_trajectory()
	if camera and camera.has_method("set_aiming"):
		camera.set_aiming(true)


func _update_aim(delta: float) -> void:
	if camera and camera.has_method("get_aim_forward"):
		var forward: Vector3 = camera.get_aim_forward()
		aim_direction = Vector3(forward.x, 0.5, forward.z).normalized()

	aim_power = clamp(aim_power + delta * s_charge_rate, 0.0, s_max_power)

	if power_meter_ui:
		power_meter_ui.update_power(aim_power, s_max_power)


func _confirm_shot() -> void:
	var direction := aim_direction
	var power := aim_power

	# Apply accuracy variance — random horizontal spread before sending to network
	var spread: float = (1.0 - _accuracy) * 0.10
	if spread > 0.001:
		var angle_offset: float = randf_range(-spread, spread)
		direction = direction.rotated(Vector3.UP, angle_offset)

	_cancel_aim()
	if direction != Vector3.ZERO:
		shot_ready.emit(direction, power)


func _cancel_aim() -> void:
	is_aiming = false
	aim_power = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if power_meter_ui:
		power_meter_ui.hide_meter()
	trajectory_drawer.hide_trajectory()
	if camera and camera.has_method("set_aiming"):
		camera.set_aiming(false)


# -------------------------------------------------------------------------
# Shot execution — called for ALL players (local and remote) via NetworkManager
# -------------------------------------------------------------------------

## Starts physics simulation from the given shot parameters.
## Called after the server has validated and broadcast the shot.
func play_shot(direction: Vector3, power: float) -> void:
	last_shot_position = global_position
	var initial_velocity := (direction * power * _power_multiplier) / sim_params.mass
	sim_state = PhysicsSimulator.SimulationState.new(global_position, initial_velocity)
	is_simulating = true
	freeze = true


# -------------------------------------------------------------------------
# Physics simulation
# -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_simulating:
		_simulate_step(delta)


func _simulate_step(delta: float) -> void:
	sim_state = PhysicsSimulator.simulate_step(sim_state, sim_params, delta)
	var collision := move_and_collide(sim_state.velocity * delta)

	if collision:
		var normal := collision.get_normal()
		if normal.y < 0.7:
			# Non-ground obstacle (tree, wall) — reflect velocity so ball doesn't phase through
			sim_state.velocity = sim_state.velocity.bounce(normal) * 0.6

	# Out-of-bounds check using the current hole's terrain bounds
	if not _bounds_check.is_null() and _bounds_check.call(global_position):
		_handle_out_of_bounds()
		return

	ball_moved.emit(global_position)

	if PhysicsSimulator.is_stopped(sim_state, STOP_VELOCITY_THRESHOLD):
		is_simulating = false
		freeze = false
		ball_at_rest.emit(peer_id)


func _handle_out_of_bounds() -> void:
	is_simulating = false
	freeze = false
	global_position = last_shot_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sim_state = PhysicsSimulator.SimulationState.new(last_shot_position, Vector3.ZERO)
	out_of_bounds.emit(peer_id)


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func is_at_rest() -> bool:
	return not is_simulating and linear_velocity.length() < 0.1


func reset_position(pos: Vector3) -> void:
	global_position = pos
	last_shot_position = pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	is_simulating = false
	freeze = false
