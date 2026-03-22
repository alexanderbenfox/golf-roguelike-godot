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

## Emitted when the ball lands in water. Ball is teleported back automatically.
signal hit_water(peer_id: int)

## Emitted when the ball contacts lava. Ball bounces out automatically.
signal hit_lava(peer_id: int)

# ---- Identity --------------------------------------------------------------

## Set by the scene that owns this ball so signals carry the right peer_id.
var peer_id: int = 1

## True when this ball belongs to the local player (shows input UI, reads input).
var is_local_player: bool = true

# ---- Club & Swing ----------------------------------------------------------

## Club bag — set from PlayerState during setup
var club_bag: Array[Resource] = []
var selected_club_index: int = 0

## Current launch angle in degrees (adjusted by player during free aim)
var current_angle_deg: float = 28.0

## Cup position for distance-to-pin display — set by Main each hole
var cup_position: Vector3 = Vector3.ZERO

## Swing timing state machine
var swing: SwingState = SwingState.new()

# ---- Aiming state ----------------------------------------------------------

var is_aiming: bool = false
var aim_direction: Vector3 = Vector3.ZERO
var aim_power: float = 0.0

# Throttle for terrain band recomputation during free aim
var _band_recompute_timer: float = 0.0
var _last_band_direction: Vector3 = Vector3.ZERO
const BAND_RECOMPUTE_INTERVAL: float = 0.3
const BAND_DIRECTION_THRESHOLD: float = 0.02

@export var s_max_power: float = 10.0
@export var s_charge_rate: float = 1.5

# ---- Simulation state ------------------------------------------------------

var is_simulating: bool = false
var sim_state: PhysicsSimulator.SimulationState
var sim_params: PhysicsSimulator.PhysicsParams
var _power_multiplier: float = 1.0
var _accuracy: float = 0.7
var last_shot_position: Vector3 = Vector3.ZERO
var _last_camera_angle: float = 0.0
var _last_camera_height_offset: float = 0.0
var _bounds_check: Callable

const STOP_VELOCITY_THRESHOLD: float = 0.02
const MAX_LAVA_BOUNCES: int = 3

var _lava_bounce_count: int = 0
var _lava_penalty_emitted: bool = false

# ---- Node references (set via @export so scene wiring is explicit) ---------

## New swing UI elements — set by Main after creation
var terrain_power_meter: TerrainPowerMeter
var angle_display: AngleDisplay
var club_selector_ui: ClubSelectorUI

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

# Guards against double-consuming the first press in the same frame
var _swing_started_this_frame: bool = false


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

	_load_default_club_bag()

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

	# Wind is set separately via set_wind() after hole layout is known
	sim_params.wind = Vector3.ZERO

	# Apply roguelike modifiers if a PlayerState is provided
	if player:
		sim_params.ball_bounce *= player.bounce_modifier
		sim_params.ground_friction *= player.friction_modifier
		sim_params.gravity_scale *= player.gravity_scale
		_power_multiplier = player.power_multiplier
		_accuracy = player.accuracy

		# Load club bag from player state
		if player.club_bag.size() > 0:
			club_bag = player.club_bag
			if selected_club_index >= club_bag.size():
				selected_club_index = 0
			var club: ClubDefinition = get_selected_club()
			if club:
				current_angle_deg = club.default_angle_deg

	# Apply selected club's landing modifiers
	var club: ClubDefinition = get_selected_club()
	if club:
		sim_params.ball_bounce *= club.landing_bounce
		sim_params.ground_friction *= club.landing_friction


## Set the wind vector for the current hole (called by Main after hole setup).
func set_wind(wind: Vector3) -> void:
	if sim_params:
		sim_params.wind = wind


## Apply an external impulse to the ball (e.g. from a dynamic hazard).
## If the ball is at rest, restarts simulation so the impulse takes effect.
## Cancels any in-progress aim so the player can't shoot mid-launch.
func apply_hazard_impulse(impulse: Vector3) -> void:
	if not sim_state:
		return
	if is_aiming:
		_cancel_aim()
	if not is_simulating:
		# Ball is at rest — restart simulation with the impulse as velocity
		sim_state.velocity = impulse
		sim_state.position = global_position
		is_simulating = true
		freeze = true
		ball_trail.start()
		if camera and camera.has_method("start_follow_shot"):
			camera.start_follow_shot()
	else:
		sim_state.velocity += impulse


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
		trajectory_drawer.hide_trajectory()
		if terrain_power_meter:
			terrain_power_meter.hide_meter()
		if angle_display:
			angle_display.hide_display()
		if club_selector_ui:
			club_selector_ui.hide_selector()


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

	# Free aim: angle adjustment and club cycling before swing starts
	if is_local_player and _turn_active and is_at_rest():
		_handle_club_cycling()
		if not swing.is_active():
			_handle_angle_input(delta)
		# Show club selector and angle display while turn is active
		_update_free_aim_ui()

	if actionable:
		if Input.is_action_just_pressed("golf_shoot"):
			_start_aiming()

	if is_aiming:
		_update_aim(delta)

		# Input flow: press-down starts power fill, release locks power and fires.
		if swing.phase == SwingState.Phase.POWER_FILL:
			if Input.is_action_just_released("golf_shoot") and not _swing_started_this_frame:
				swing.press()  # release → lock power, complete swing
		_swing_started_this_frame = false

		# Check if swing completed
		if swing.phase == SwingState.Phase.COMPLETE:
			_confirm_shot()


func _handle_club_cycling() -> void:
	if club_bag.size() <= 1:
		return
	# Disable cycling once swing has started
	if swing.is_active():
		return
	if Input.is_action_just_pressed("club_next"):
		_select_club((selected_club_index + 1) % club_bag.size())
	elif Input.is_action_just_pressed("club_prev"):
		_select_club((selected_club_index - 1 + club_bag.size()) % club_bag.size())


func _select_club(index: int) -> void:
	selected_club_index = index
	var club: ClubDefinition = get_selected_club()
	if club:
		current_angle_deg = club.default_angle_deg


func _handle_angle_input(delta: float) -> void:
	var club: ClubDefinition = get_selected_club()
	if not club:
		return
	var angle_speed: float = 30.0  # degrees per second when holding
	if Input.is_action_pressed("angle_up"):
		current_angle_deg = minf(current_angle_deg + angle_speed * delta, club.max_angle_deg)
	elif Input.is_action_pressed("angle_down"):
		current_angle_deg = maxf(current_angle_deg - angle_speed * delta, club.min_angle_deg)


func get_selected_club() -> ClubDefinition:
	if club_bag.size() == 0:
		return null
	return club_bag[selected_club_index] as ClubDefinition


func _update_free_aim_ui() -> void:
	var club: ClubDefinition = get_selected_club()
	if angle_display:
		angle_display.show_display()
		angle_display.update_angle(current_angle_deg)
	if club_selector_ui and club:
		club_selector_ui.show_selector()
		var dist_to_pin: float = _get_distance_to_pin()
		club_selector_ui.update_club(club, dist_to_pin)
		club_selector_ui.set_arrows_visible(
			club_bag.size() > 1, club_bag.size() > 1
		)

	# Show a ghost trajectory at 50% power so player can see aim direction
	if not is_aiming and sim_params and camera and camera.has_method("get_aim_forward"):
		var forward: Vector3 = camera.get_aim_forward()
		var angle_rad: float = deg_to_rad(current_angle_deg)
		var horizontal: float = cos(angle_rad)
		var vertical: float = sin(angle_rad)
		var preview_dir: Vector3 = Vector3(
			forward.x * horizontal, vertical, forward.z * horizontal
		).normalized()
		var power_scale: float = club.power_scale if club else 1.0
		var preview_power: float = 0.5 * s_max_power * power_scale
		trajectory_drawer.global_position = Vector3.ZERO
		trajectory_drawer.show_trajectory()
		trajectory_drawer.draw_trajectory(
			sim_params,
			preview_dir * preview_power * _power_multiplier,
			_accuracy,
			global_position,
		)

		# Show terrain power meter during free aim with throttled band updates
		if terrain_power_meter:
			terrain_power_meter.show_meter()
			terrain_power_meter.update_power(0.0)
			# Recompute bands when direction changes or timer expires
			var dir_changed: bool = preview_dir.distance_to(_last_band_direction) > BAND_DIRECTION_THRESHOLD
			_band_recompute_timer -= get_process_delta_time()
			if dir_changed or _band_recompute_timer <= 0.0:
				aim_direction = preview_dir
				_compute_terrain_bands()
				_last_band_direction = preview_dir
				_band_recompute_timer = BAND_RECOMPUTE_INTERVAL


func _get_distance_to_pin() -> float:
	if cup_position == Vector3.ZERO:
		return 0.0
	return Vector3(
		global_position.x - cup_position.x, 0.0,
		global_position.z - cup_position.z
	).length()


func _start_aiming() -> void:
	is_aiming = true
	aim_power = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Configure swing state from selected club
	var club: ClubDefinition = get_selected_club()
	if club:
		swing.configure(club, _accuracy)
	swing.press()  # First press → starts power fill
	_swing_started_this_frame = true

	if terrain_power_meter:
		terrain_power_meter.show_meter()
		terrain_power_meter.set_overshooting(false, 0.0)
		_compute_terrain_bands()
	trajectory_drawer.show_trajectory()
	if camera and camera.has_method("set_aiming"):
		camera.set_aiming(true)


func _update_aim(delta: float) -> void:
	var prev_phase: SwingState.Phase = swing.phase
	swing.update(delta)

	if camera and camera.has_method("get_aim_forward"):
		var forward: Vector3 = camera.get_aim_forward()
		var angle_rad: float = deg_to_rad(current_angle_deg)
		var horizontal: float = cos(angle_rad)
		var vertical: float = sin(angle_rad)
		aim_direction = Vector3(
			forward.x * horizontal, vertical, forward.z * horizontal
		).normalized()

	# Derive aim_power from swing state for trajectory preview and power meter
	var club: ClubDefinition = get_selected_club()
	var power_scale: float = club.power_scale if club else 1.0
	aim_power = swing.get_power_normalized() * s_max_power * power_scale

	# Update terrain power meter
	if terrain_power_meter:
		terrain_power_meter.update_power(swing.get_power_normalized())
		terrain_power_meter.set_overshooting(swing.is_overshooting(), swing.get_overshoot())

	# Update trajectory preview during power fill
	if swing.phase == SwingState.Phase.POWER_FILL:
		trajectory_drawer.global_position = Vector3.ZERO
		trajectory_drawer.draw_trajectory(
			sim_params,
			aim_direction * aim_power * _power_multiplier,
			_accuracy,
			global_position,
		)


func _confirm_shot() -> void:
	var direction := aim_direction
	var outcome: SwingState.SwingOutcome = swing.result

	# Apply power from swing result
	var club: ClubDefinition = get_selected_club()
	var power_scale: float = club.power_scale if club else 1.0
	var power: float = outcome.power_percent * s_max_power * power_scale * outcome.power_bonus

	# Apply accuracy deviation from swing timing (replaces old random spread)
	if absf(outcome.deviation_deg) > 0.01:
		direction = direction.rotated(Vector3.UP, deg_to_rad(outcome.deviation_deg))

	swing.reset()
	_cancel_aim()
	if direction != Vector3.ZERO:
		shot_ready.emit(direction, power)


func _cancel_aim() -> void:
	is_aiming = false
	aim_power = 0.0
	swing.reset()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if terrain_power_meter:
		terrain_power_meter.hide_meter()
	if angle_display:
		angle_display.hide_display()
	if club_selector_ui:
		club_selector_ui.hide_selector()
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
	# Save camera orbit angles so we can restore them on water/OOB teleport
	if camera:
		_last_camera_angle = camera.camera_angle
		_last_camera_height_offset = camera.camera_height_offset
	_lava_bounce_count = 0
	_lava_penalty_emitted = false
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

	if sim_state.is_on_ground:
		# On ground — simulator handles terrain via heightmap.
		# Set position directly to avoid terrain mesh eating momentum.
		global_position = sim_state.position
	else:
		# Airborne — use move_and_collide for wall/obstacle detection
		var motion: Vector3 = sim_state.position - global_position
		var collision := move_and_collide(motion)
		if collision:
			var normal := collision.get_normal()
			var impact_speed := absf(sim_state.velocity.dot(normal))
			if normal.y < 0.5 and impact_speed > 2.0:
				# Real wall impact — bounce off
				sim_state.velocity = sim_state.velocity.bounce(normal) * 0.6
				_spawn_impact_flash(collision.get_position(), 0.6)
				sim_state.position = global_position
			else:
				# Terrain or gentle impact — trust the simulator's heightmap
				global_position = sim_state.position
		else:
			# No collision — positions match
			sim_state.position = global_position

	# Out-of-bounds check using the current hole's terrain bounds
	if not _bounds_check.is_null() and _bounds_check.call(global_position):
		_handle_out_of_bounds()
		return

	# Lava check — bounce the ball out immediately on contact
	if sim_state.is_on_ground and _check_lava():
		return

	# Feed velocity to the follow camera and trail each frame
	if camera and camera.has_method("set_follow_velocity"):
		camera.set_follow_velocity(sim_state.velocity)
	ball_trail.add_point(global_position, sim_state.velocity)

	ball_moved.emit(global_position)

	if PhysicsSimulator.is_stopped(sim_state, STOP_VELOCITY_THRESHOLD, sim_params):
		# Water check — teleport back when ball comes to rest in water
		if _check_water():
			return
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
	_restore_camera_angles()
	out_of_bounds.emit(peer_id)


# -------------------------------------------------------------------------
# Hazard detection
# -------------------------------------------------------------------------

## Returns true (and handles the hazard) if ball is in water.
func _check_water() -> bool:
	if not sim_params.terrain:
		return false
	var pos: Vector3 = global_position
	if not sim_params.terrain.is_water_at(pos.x, pos.z):
		return false
	_handle_water_hazard()
	return true


## Returns true (and handles the hazard) if ball is on lava.
func _check_lava() -> bool:
	if not sim_params.terrain:
		return false
	var pos: Vector3 = global_position
	if not sim_params.terrain.is_lava_at(pos.x, pos.z):
		return false
	_handle_lava_bounce()
	return true


func _handle_water_hazard() -> void:
	is_simulating = false
	freeze = false
	ball_trail.stop()
	if camera and camera.has_method("stop_follow_shot"):
		camera.stop_follow_shot()
	global_position = last_shot_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sim_state = PhysicsSimulator.SimulationState.new(
		last_shot_position, Vector3.ZERO,
	)
	_restore_camera_angles()
	hit_water.emit(peer_id)


func _handle_lava_bounce() -> void:
	_lava_bounce_count += 1
	# Emit penalty signal only on first contact
	if not _lava_penalty_emitted:
		_lava_penalty_emitted = true
		hit_lava.emit(peer_id)
	# Too many bounces — force teleport like water
	if _lava_bounce_count > MAX_LAVA_BOUNCES:
		_handle_water_hazard()
		return
	# Bounce upward + push away from lava toward safe ground
	var bounce_speed: float = 4.0 + randf() * 2.0
	var lateral_dir: Vector3
	if last_shot_position.distance_to(global_position) > 1.0:
		lateral_dir = (last_shot_position - global_position).normalized()
		lateral_dir.y = 0.0
		lateral_dir = lateral_dir.normalized()
	else:
		var angle: float = randf() * TAU
		lateral_dir = Vector3(cos(angle), 0.0, sin(angle))
	sim_state.velocity = Vector3.UP * bounce_speed + lateral_dir * 3.0
	sim_state.is_on_ground = false


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func _restore_camera_angles() -> void:
	if camera:
		camera.camera_angle = _last_camera_angle
		camera.snap_to_target()
		# Restore height offset after snap (snap resets it to 0)
		camera.camera_height_offset = _last_camera_height_offset


func _compute_terrain_bands() -> void:
	if not terrain_power_meter or not sim_params:
		return
	var club: ClubDefinition = get_selected_club()
	var power_scale: float = club.power_scale if club else 1.0
	var bands: Array[Dictionary] = []

	# Sample at 20 power levels (every 5%)
	for i: int in range(1, 21):
		var pct: float = float(i) / 20.0
		var sample_power: float = pct * s_max_power * power_scale
		var impulse: Vector3 = aim_direction * sample_power * _power_multiplier
		var velocity: Vector3 = impulse / sim_params.mass

		var positions: Array[Vector3] = PhysicsSimulator.simulate_trajectory(
			velocity, sim_params, global_position, 0.05, 10.0, 0.1
		)

		var zone_color := Color(0.2, 0.2, 0.2)
		var zone_type: int = -1
		if positions.size() >= 2 and sim_params.terrain:
			var landing: Vector3 = positions[positions.size() - 1]
			zone_type = sim_params.terrain.get_zone_at(landing.x, landing.z)
			# Get color from terrain's biome zones if available
			zone_color = sim_params.terrain.get_zone_color(zone_type)

		bands.append({
			"percent": pct,
			"color": zone_color,
			"zone_type": zone_type,
		})

	# Prepend a 0% entry matching the first band
	if bands.size() > 0:
		var first: Dictionary = bands[0].duplicate()
		first["percent"] = 0.0
		bands.insert(0, first)

	terrain_power_meter.set_bands(bands)


func _load_default_club_bag() -> void:
	if club_bag.size() > 0:
		return
	var paths: Array[String] = [
		"res://resources/clubs/driver.tres",
		"res://resources/clubs/iron_5.tres",
		"res://resources/clubs/hybrid.tres",
		"res://resources/clubs/wedge_pitching.tres",
		"res://resources/clubs/putter.tres",
	]
	for path: String in paths:
		var res: Resource = load(path)
		if res:
			club_bag.append(res)
	if club_bag.size() > 0:
		_select_club(0)


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
