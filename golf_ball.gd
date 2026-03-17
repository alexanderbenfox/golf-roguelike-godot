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

@onready var trajectory_drawer: TrajectoryDrawer
@onready var ball_trail: Node3D
@onready var camera: Camera3D = get_viewport().get_camera_3d()

# ---- Whether this ball is allowed to accept input this frame ---------------
# Set by TurnManager via set_turn_active().
var _turn_active: bool = false

# ---- Ready indicator -------------------------------------------------------
var _ready_ring: Decal
var _ready_ring_tween: Tween
var _shadow_decal: Decal

# Brief flag to ignore cup collisions right after a position reset
var _ignore_cup: bool = false


# -------------------------------------------------------------------------
# Lifecycle
# -------------------------------------------------------------------------

var _initialized: bool = false

func _ready() -> void:
	if _initialized:
		return
	_initialized = true

	contact_monitor = true
	max_contacts_reported = 4
	add_to_group("ball")

	trajectory_drawer = TrajectoryDrawer.new()
	add_child(trajectory_drawer)

	var trail_script: GDScript = preload("res://scripts/utility/ball_trail.gd")
	ball_trail = trail_script.new()
	add_child(ball_trail)

	_create_shadow_decal()
	_create_ready_ring()

	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	setup_physics_params()


# -------------------------------------------------------------------------
# Physics params — built from the Godot node properties + optional modifiers
# -------------------------------------------------------------------------

func setup_physics_params(
	player: PlayerState = null, terrain: RefCounted = null
) -> void:
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

	# Terrain heightmap (null = flat ground at ground_height)
	sim_params.terrain = terrain

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
	# Keep top-level decals following ball position without inheriting rotation
	var decal_pos: Vector3 = global_position + Vector3(0.0, -0.1, 0.0)
	if _shadow_decal:
		_shadow_decal.global_position = decal_pos
	if _ready_ring:
		_ready_ring.global_position = decal_pos

	var actionable: bool = is_local_player and _turn_active and is_at_rest() and not is_aiming
	_update_ready_ring(actionable)

	if actionable:
		if Input.is_action_just_pressed("golf_shoot"):
			_start_aiming()

	if is_aiming:
		_update_aim(delta)
		trajectory_drawer.global_position = Vector3.ZERO
		trajectory_drawer.draw_trajectory(
			sim_params,
			aim_direction * aim_power * _power_multiplier,
			_accuracy,
			global_position,
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
	_spawn_impact_flash(global_position, 1.5)
	ball_trail.start()
	if camera and camera.has_method("start_follow_shot"):
		camera.start_follow_shot()


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
			sim_state.velocity = sim_state.velocity.bounce(normal) * 0.6
			_spawn_impact_flash(collision.get_position(), 0.6)

	# Keep sim state in sync with actual node position after collision resolution
	sim_state.position = global_position

	# Out-of-bounds check using the current hole's terrain bounds
	if not _bounds_check.is_null() and _bounds_check.call(global_position):
		_handle_out_of_bounds()
		return

	# Feed velocity to the follow camera and trail each frame
	if camera and camera.has_method("set_follow_velocity"):
		camera.set_follow_velocity(sim_state.velocity)
	ball_trail.add_point(global_position, sim_state.velocity)

	ball_moved.emit(global_position)

	if PhysicsSimulator.is_stopped(sim_state, STOP_VELOCITY_THRESHOLD):
		sim_state.velocity = Vector3.ZERO
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		is_simulating = false
		ball_trail.stop()
		if camera and camera.has_method("stop_follow_shot"):
			camera.stop_follow_shot()
		ball_at_rest.emit(peer_id)


func _handle_out_of_bounds() -> void:
	is_simulating = false
	freeze = false
	ball_trail.stop()
	if camera and camera.has_method("stop_follow_shot"):
		camera.stop_follow_shot()
	global_position = last_shot_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sim_state = PhysicsSimulator.SimulationState.new(last_shot_position, Vector3.ZERO)
	out_of_bounds.emit(peer_id)


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func _create_ready_ring() -> void:
	_ready_ring = Decal.new()
	_ready_ring.size = Vector3(2.0, 20.0, 2.0)
	_ready_ring.position = Vector3(0.0, -0.1, 0.0)

	# Ring shape: transparent center, bright band, transparent edge
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.3, 0.9, 0.4, 0.0))
	gradient.add_point(0.55, Color(0.3, 0.9, 0.4, 0.0))
	gradient.add_point(0.7, Color(0.3, 0.9, 0.4, 0.7))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.3, 0.9, 0.4, 0.0))
	gradient.set_offset(gradient.get_point_count() - 1, 1.0)

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64

	_ready_ring.texture_albedo = tex
	_ready_ring.upper_fade = 0.0
	_ready_ring.lower_fade = 0.2
	_ready_ring.cull_mask = 1
	_ready_ring.visible = false
	_ready_ring.top_level = true
	add_child(_ready_ring)


func _update_ready_ring(actionable: bool) -> void:
	if not _ready_ring:
		return
	if actionable and not _ready_ring.visible:
		_ready_ring.visible = true
		_ready_ring.modulate.a = 1.0
		# Start a looping pulse
		if _ready_ring_tween:
			_ready_ring_tween.kill()
		_ready_ring_tween = create_tween().set_loops()
		_ready_ring_tween.tween_property(_ready_ring, "modulate:a", 0.4, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_ready_ring_tween.tween_property(_ready_ring, "modulate:a", 1.0, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not actionable and _ready_ring.visible:
		_ready_ring.visible = false
		if _ready_ring_tween:
			_ready_ring_tween.kill()
			_ready_ring_tween = null


func _create_shadow_decal() -> void:
	var decal := Decal.new()
	decal.size = Vector3(1.5, 20.0, 1.5)
	decal.position = Vector3(0.0, -0.1, 0.0)

	# Radial gradient: dark center fading to transparent edge
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.5))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	gradient.set_offset(0, 0.0)
	gradient.set_offset(1, 1.0)

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64

	decal.texture_albedo = tex
	decal.upper_fade = 0.0
	decal.lower_fade = 0.2
	decal.cull_mask = 1
	decal.top_level = true
	add_child(decal)
	_shadow_decal = decal


func _spawn_impact_flash(pos: Vector3, scale_mult: float = 1.0) -> void:
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 90.0
	mat.initial_velocity_min = 2.0 * scale_mult
	mat.initial_velocity_max = 5.0 * scale_mult
	mat.gravity = Vector3(0.0, -8.0, 0.0)
	mat.scale_min = 0.8
	mat.scale_max = 1.5

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(1.0, 1.0, 0.9, 0.9)
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat

	particles.process_material = mat
	particles.draw_pass_1 = mesh
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = int(12 * scale_mult)
	particles.lifetime = 0.5
	particles.global_position = pos

	get_tree().root.add_child(particles)
	get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


func _clear_ignore_cup() -> void:
	_ignore_cup = false


func is_at_rest() -> bool:
	return not is_simulating


func reset_position(pos: Vector3) -> void:
	is_simulating = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	last_shot_position = pos
	if sim_state:
		sim_state.position = pos
		sim_state.velocity = Vector3.ZERO
	# Remove and re-add to force the physics server to pick up the new position.
	# Setting transforms directly doesn't work after move_and_collide desync.
	_ignore_cup = true
	var parent_node: Node = get_parent()
	parent_node.remove_child(self)
	transform = Transform3D.IDENTITY
	if parent_node is Node3D:
		(parent_node as Node3D).global_position = pos
	parent_node.add_child(self)
	# Clear the cup-ignore flag after physics has settled
	get_tree().physics_frame.connect(_clear_ignore_cup, CONNECT_ONE_SHOT)
