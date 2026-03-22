extends Camera3D

const PolylineUtilsScript = preload("res://scripts/utility/polyline_utils.gd")

enum Mode { ORBIT, FOLLOW_SHOT, FLYOVER }

@export var follow_target: Node3D
@export var distance: float = 10.0
@export var height: float = 5.0
@export var min_height: float = 1.0
@export var max_height: float = 15.0
@export var keyboard_rotation_speed: float = 2.0
@export var controller_rotation_speed: float = 3.0
@export var vertical_speed: float = 2.0
@export var mouse_sensitivity: float = 0.005
@export var smoothness: float = 8.0
@export var ground_check_layers: int = 1

var camera_angle: float = 0.0
var camera_height_offset: float = 0.0
var input_enabled: bool = true

# Aim offset — shifts camera laterally when aiming to reveal the trajectory arc
const AIM_LATERAL_OFFSET: float = 2.5
const AIM_HEIGHT_BOOST: float = 1.5
const AIM_OFFSET_SPEED: float = 4.0

var _aim_offset_active: bool = false
var _current_aim_lateral: float = 0.0
var _current_aim_height: float = 0.0

# Follow-shot mode — chase cam behind the ball during flight
const FOLLOW_DISTANCE: float = 5.0
const FOLLOW_HEIGHT: float = 2.5
const FOLLOW_SMOOTHNESS: float = 4.0
const FOLLOW_LOOK_AHEAD: float = 3.0

var _mode: Mode = Mode.ORBIT
var _follow_velocity: Vector3 = Vector3.ZERO
var _last_follow_dir: Vector3 = Vector3.FORWARD

# Flyover mode — cinematic pan along the course (Mario Kart style)
const FLYOVER_HEIGHT: float = 20.0
const FLYOVER_LOOK_AHEAD_T: float = 0.08
const FLYOVER_SMOOTHNESS: float = 5.0

var _flyover_spine: Array[Vector3] = []
var _flyover_progress: float = 0.0
var _flyover_duration: float = 3.0

signal flyover_completed


## Immediately snap the camera to its orbit position around the follow target.
## Call this after teleporting the ball (e.g. new hole) to avoid a slow lerp.
func snap_to_target() -> void:
	if not follow_target:
		return
	camera_height_offset = 0.0
	_current_aim_lateral = 0.0
	_current_aim_height = 0.0
	var pos := follow_target.global_position + Vector3(
		sin(camera_angle) * distance,
		height,
		cos(camera_angle) * distance
	)
	global_position = pos
	look_at(follow_target.global_position + Vector3(0.0, 0.5, 0.0))


func set_aiming(active: bool) -> void:
	_aim_offset_active = active


func get_aim_forward() -> Vector3:
	return Vector3(
		-sin(camera_angle), 0.0, -cos(camera_angle)
	).normalized()


func start_follow_shot() -> void:
	_mode = Mode.FOLLOW_SHOT
	_last_follow_dir = get_aim_forward()


func set_follow_velocity(vel: Vector3) -> void:
	_follow_velocity = vel
	var horizontal := Vector3(vel.x, 0.0, vel.z)
	if horizontal.length() > 0.3:
		var target_dir: Vector3 = horizontal.normalized()
		_last_follow_dir = _last_follow_dir.slerp(target_dir, 0.05)


func stop_follow_shot() -> void:
	_mode = Mode.ORBIT
	# Sync orbit angle to current camera position for seamless transition
	if follow_target:
		var offset: Vector3 = global_position - follow_target.global_position
		camera_angle = atan2(offset.x, offset.z)


## Start a cinematic flyover along the course spine (cup → tee).
## Duration auto-scales by spine length: ~1s per 100m, clamped 2-5s.
func start_flyover(spine: Array[Vector3]) -> void:
	_mode = Mode.FLYOVER
	input_enabled = false
	# Reverse spine so camera flies from cup → tee
	_flyover_spine = spine.duplicate()
	_flyover_spine.reverse()
	_flyover_progress = 0.0
	# Scale duration by spine length
	var spine_length: float = PolylineUtilsScript.total_length(_flyover_spine)
	_flyover_duration = clampf(spine_length / 100.0, 2.0, 5.0)
	# Snap to start position
	var start_pos: Vector3 = _flyover_spine[0]
	global_position = Vector3(start_pos.x, start_pos.y + FLYOVER_HEIGHT, start_pos.z)


## Skip the flyover and jump straight to orbit mode.
func skip_flyover() -> void:
	if _mode == Mode.FLYOVER:
		_end_flyover()


func _end_flyover() -> void:
	_mode = Mode.ORBIT
	input_enabled = true
	flyover_completed.emit()


func _process(delta: float) -> void:
	# Flyover mode — cinematic spine pan
	if _mode == Mode.FLYOVER:
		_process_flyover(delta)
		return

	if not follow_target:
		return

	# Smoothly lerp aim offsets (always runs so offset returns to 0)
	var target_lateral: float = AIM_LATERAL_OFFSET if _aim_offset_active else 0.0
	var target_height: float = AIM_HEIGHT_BOOST if _aim_offset_active else 0.0
	_current_aim_lateral = lerpf(
		_current_aim_lateral, target_lateral, AIM_OFFSET_SPEED * delta
	)
	_current_aim_height = lerpf(
		_current_aim_height, target_height, AIM_OFFSET_SPEED * delta
	)

	# Follow-shot mode — chase behind the ball
	if _mode == Mode.FOLLOW_SHOT:
		_process_follow_shot(delta)
		return

	var lat_dir: Vector3 = Vector3(
		cos(camera_angle), 0.0, -sin(camera_angle)
	)

	if not input_enabled:
		var base_pos: Vector3 = follow_target.global_position + Vector3(
			sin(camera_angle) * distance,
			height + camera_height_offset + _current_aim_height,
			cos(camera_angle) * distance
		) + lat_dir * _current_aim_lateral
		global_position = global_position.lerp(base_pos, smoothness * delta)
		look_at(follow_target.global_position + Vector3(0.0, 0.5, 0.0))
		return

	var controller_input: float = Input.get_axis("camera_left", "camera_right")

	var rotation_input: float = controller_input
	camera_angle += rotation_input * keyboard_rotation_speed * delta

	if abs(controller_input) > 0.1:
		camera_angle += controller_input * (
			controller_rotation_speed - keyboard_rotation_speed
		)

	var vertical_input: float = 0.0

	controller_input = Input.get_axis("camera_down_stick", "camera_up_stick")
	vertical_input += controller_input
	camera_height_offset += vertical_input * vertical_speed * delta
	camera_height_offset = clamp(
		camera_height_offset,
		-(height - min_height),
		max_height - height,
	)

	var horiz_offset := Vector3(
		sin(camera_angle) * distance, 0.0, cos(camera_angle) * distance
	)
	var current_height := height + camera_height_offset + _current_aim_height
	var desired_pos := (
		follow_target.global_position
		+ horiz_offset
		+ Vector3(0.0, current_height, 0.0)
	)

	# Apply lateral aim offset
	desired_pos += lat_dir * _current_aim_lateral

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		desired_pos + Vector3(0.0, 10.0, 0.0),
		desired_pos + Vector3(0.0, -100.0, 0.0)
	)
	query.collision_mask = ground_check_layers

	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		var ground_height: float = (result["position"] as Vector3).y
		var adjusted_height: float = max(ground_height + min_height, desired_pos.y)
		desired_pos.y = adjusted_height

	# Terrain occlusion — pull camera closer if terrain blocks view of the ball
	var ball_center: Vector3 = follow_target.global_position + Vector3(0.0, 0.5, 0.0)
	var occlusion_query := PhysicsRayQueryParameters3D.create(
		ball_center, desired_pos
	)
	occlusion_query.collision_mask = ground_check_layers
	var occlusion_result: Dictionary = space_state.intersect_ray(occlusion_query)
	if occlusion_result:
		var hit_pos: Vector3 = occlusion_result["position"]
		# Place camera 85% of the way from ball to hit point
		desired_pos = ball_center.lerp(hit_pos, 0.85)
		# Ensure camera stays above a minimum height relative to ball
		desired_pos.y = maxf(
			desired_pos.y,
			follow_target.global_position.y + min_height,
		)

	global_position = global_position.lerp(desired_pos, smoothness * delta)
	look_at(follow_target.global_position + Vector3(0.0, 0.5, 0.0))


func _process_follow_shot(delta: float) -> void:
	var ball_pos: Vector3 = follow_target.global_position
	var behind: Vector3 = -_last_follow_dir

	var desired_pos: Vector3 = (
		ball_pos
		+ behind * FOLLOW_DISTANCE
		+ Vector3(0.0, FOLLOW_HEIGHT, 0.0)
	)

	global_position = global_position.lerp(
		desired_pos, FOLLOW_SMOOTHNESS * delta
	)

	var look_target: Vector3 = (
		ball_pos + _last_follow_dir * FOLLOW_LOOK_AHEAD
	)
	look_at(look_target)


func _process_flyover(delta: float) -> void:
	_flyover_progress += delta / _flyover_duration
	if _flyover_progress >= 1.0:
		_flyover_progress = 1.0
		_end_flyover()
		return

	# Camera position: sample spine at current progress, elevated
	var cam_pos: Vector3 = PolylineUtilsScript.sample_position(
		_flyover_spine, _flyover_progress,
	)
	cam_pos.y += FLYOVER_HEIGHT

	# Look-ahead: sample slightly further along the spine
	var look_t: float = minf(_flyover_progress + FLYOVER_LOOK_AHEAD_T, 1.0)
	var look_pos: Vector3 = PolylineUtilsScript.sample_position(
		_flyover_spine, look_t,
	)
	# Look downward at the course, not at flyover height
	look_pos.y += FLYOVER_HEIGHT * 0.3

	# Slight lateral offset for cinematic feel
	var fly_dir: Vector3 = PolylineUtilsScript.sample_direction(
		_flyover_spine, _flyover_progress,
	)
	var fly_right: Vector3 = PolylineUtilsScript.direction_to_right(fly_dir)
	cam_pos += fly_right * 5.0

	global_position = global_position.lerp(cam_pos, FLYOVER_SMOOTHNESS * delta)
	look_at(look_pos)


func _input(event: InputEvent) -> void:
	# During flyover, any key/button press skips it
	if _mode == Mode.FLYOVER:
		if event is InputEventKey or event is InputEventJoypadButton:
			if event.pressed:
				_end_flyover()
		return
	if not input_enabled:
		return
	if _mode == Mode.FOLLOW_SHOT:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		camera_angle -= motion.relative.x * mouse_sensitivity
		camera_height_offset += motion.relative.y * mouse_sensitivity * 10.0
		camera_height_offset = clamp(
			camera_height_offset,
			-(height - min_height),
			max_height - height,
		)
