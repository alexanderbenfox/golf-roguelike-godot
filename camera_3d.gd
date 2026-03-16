extends Camera3D

@export var followTarget: Node3D
@export var distance: float = 10.0
@export var height: float = 5.0
@export var minHeight: float = 1.0
@export var maxHeight: float = 15.0
@export var keyboardRotationSpeed: float = 2.0
@export var controllerRotationSpeed: float = 3.0
@export var verticalSpeed: float = 2.0
@export var mouseSensitivity: float = 0.005
@export var smoothness: float = 8.0
@export var groundCheckLayers: int = 1

var cameraAngle: float = 0.0
var cameraHeightOffset: float = 0.0
var input_enabled: bool = true

func _process(delta: float) -> void:
	if not followTarget:
		return

	if not input_enabled:
		# Still track the target, just don't accept new input
		global_position = global_position.lerp(
			followTarget.global_position
			+ Vector3(sin(cameraAngle) * distance, height + cameraHeightOffset, cos(cameraAngle) * distance),
			smoothness * delta
		)
		look_at(followTarget.global_position + Vector3(0.0, 0.5, 0.0))
		return

	var controllerInput: float = Input.get_axis("camera_left", "camera_right")

	var rotationInput: float = controllerInput
	cameraAngle += rotationInput * keyboardRotationSpeed * delta

	if abs(controllerInput) > 0.1:
		cameraAngle += controllerInput * (controllerRotationSpeed - keyboardRotationSpeed)

	var verticalInput: float = 0.0

	controllerInput = Input.get_axis("camera_down_stick", "camera_up_stick")
	verticalInput += controllerInput
	cameraHeightOffset += verticalInput * verticalSpeed * delta
	cameraHeightOffset = clamp(cameraHeightOffset, -(height - minHeight), maxHeight - height)

	var horizOffset := Vector3(sin(cameraAngle) * distance, 0.0, cos(cameraAngle) * distance)
	var currentHeight := height + cameraHeightOffset
	var desiredPos := followTarget.global_position + horizOffset + Vector3(0.0, currentHeight, 0.0)

	var spaceState: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		desiredPos + Vector3(0.0, 10.0, 0.0),
		desiredPos + Vector3(0.0, -100.0, 0.0)
	)
	query.collision_mask = groundCheckLayers

	var result: Dictionary = spaceState.intersect_ray(query)

	if result:
		var groundHeight: float = (result["position"] as Vector3).y
		var adjustedHeight: float = max(groundHeight + minHeight, desiredPos.y)
		desiredPos.y = adjustedHeight

	global_position = global_position.lerp(desiredPos, smoothness * delta)
	look_at(followTarget.global_position + Vector3(0.0, 0.5, 0.0))


func _input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		cameraAngle -= motion.relative.x * mouseSensitivity
		cameraHeightOffset += motion.relative.y * mouseSensitivity * 10.0
		cameraHeightOffset = clamp(cameraHeightOffset, -(height - minHeight), maxHeight - height)
