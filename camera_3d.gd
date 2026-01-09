extends Camera3D

@export var followTarget: Node3D
@export var distance = 10.0 #distance from object to follow
@export var height = 5.0 #height offset from the ground
@export var minHeight = 1.0 #min height to prevent ground clipping
@export var maxHeight = 15.0
@export var keyboardRotationSpeed = 2.0 #speed for keyboard
@export var controllerRotationSpeed = 3.0 #speed for controller
@export var verticalSpeed = 2.0
@export var mouseSensitivity = 0.005 # mouse drag sensitivity
@export var smoothness = 8.0 #camera movement smoothness
@export var groundCheckLayers = 1 #physics layers for ground detection

var cameraAngle = 0.0
var cameraHeightOffset = 0.0
var lastMousePos = Vector2.ZERO

func _process(delta):
	if not followTarget:
		return
		
	#controller rotation (right stick horizontal)
	var controllerInput = Input.get_axis("camera_left", "camera_right")
	
	#combine inputs
	var rotationInput = controllerInput
	cameraAngle += rotationInput * keyboardRotationSpeed * delta
	
	#controller has its own speed
	if abs(controllerInput) > 0.1: # deadzone
		cameraAngle += controllerInput * (controllerRotationSpeed - keyboardRotationSpeed)
		
	var verticalInput = 0.0
	
	controllerInput = Input.get_axis("camera_down_stick", "camera_up_stick")
	verticalInput += controllerInput
	cameraHeightOffset += verticalInput * verticalSpeed * delta
	cameraHeightOffset = clamp( cameraHeightOffset, -(height - minHeight), maxHeight - height)
	
	var horizOffset = Vector3(sin(cameraAngle) * distance, 0, cos(cameraAngle) * distance)
	var currentHeight = height + cameraHeightOffset
	var desiredPos = followTarget.global_position + horizOffset + Vector3(0, currentHeight, 0)
	
	#raycast from desired position down to check for ground
	var spaceState = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		desiredPos + Vector3(0, 10, 0),
		desiredPos + Vector3(0, -100, 0)
	)
	query.collision_mask = groundCheckLayers
	
	var result = spaceState.intersect_ray(query)
	
	# if we hit ground, adjust height to stay above it
	if result:
		var groundHeight = result.position.y
		var adjustedHeight = max(groundHeight + minHeight, desiredPos.y)
		desiredPos.y = adjustedHeight
		
	# smoothly move camera to desired position
	global_position = global_position.lerp(desiredPos, smoothness * delta)
	look_at(followTarget.global_position + Vector3(0, 0.5, 0))
	
	
func _input(event):
	if event is InputEventMouseMotion:
		var deltaMouse = event.position - lastMousePos
		cameraAngle -= deltaMouse.x * mouseSensitivity
		
		# Vertical movement
		cameraHeightOffset += deltaMouse.y * mouseSensitivity * 10.0
		cameraHeightOffset = clamp(cameraHeightOffset, -(height - minHeight), maxHeight - height)
		
		lastMousePos = event.position
	
