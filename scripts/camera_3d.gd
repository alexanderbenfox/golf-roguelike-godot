extends Camera3D

enum Mode { ORBIT, FOLLOW_SHOT }

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


func _process(delta: float) -> void:
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


func _input(event: InputEvent) -> void:
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
