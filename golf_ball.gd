extends RigidBody3D

# aiming dynamic variables
var isAiming = false
var aimDirection = Vector3.ZERO
var aimPower = 0.0
var ballRadius: float = 0.0

var floor_friction: float = 2.0
var floor_bounce: float = 0.3

var stop_velocity_threshold = 0.3
var stop_angular_threshold = 0.5

@export var s_maxPower = 2
@export var s_chargeRate = .2

# camera reference
@onready var camera = get_viewport().get_camera_3d()

# node references
@export var powerMeterUI: ProgressBar
@export var floorNode: StaticBody3D

@onready var trajectoryDrawer: TrajectoryDrawer

func _ready():
	contact_monitor = true
	max_contacts_reported = 4
	
	trajectoryDrawer = TrajectoryDrawer.new()
	add_child(trajectoryDrawer)
	
	for child in get_children():
		if child is CollisionShape3D:
			if child.shape is Shape3D:
				ballRadius = child.shape.radius
				break
				
	get_floor_properties()
				
func get_floor_properties():
	# Find the floor and get its physics material
	if floorNode.physics_material_override:
		floor_friction = floorNode.physics_material_override.friction
		floor_bounce = floorNode.physics_material_override.bounce
		
#func _physics_process(delta: float) -> void:
#	if not isAiming and linear_velocity.length() < stop_velocity_threshold and angular_velocity.length() < stop_angular_threshold:
#		linear_velocity = Vector3.ZERO
#		angular_velocity = Vector3.ZERO
	
func _process(delta):
	if is_at_rest() and not isAiming:
		# ball has stopped, ready to aim
		if Input.is_action_just_pressed("ui_accept"): # Space bar
			start_aiming()
	if isAiming:
		update_aim(delta)
		
		var hit_impulse = aimDirection * aimPower
		
		# get ball's physics material properties
		var ball_friction_value = 1.0
		var ball_bounce_value = 0.6
		if physics_material_override:
			ball_friction_value = physics_material_override.friction
			ball_bounce_value = physics_material_override.bounce
		
		trajectoryDrawer.draw_curved_trajectory(
			global_position,
			hit_impulse,
			mass,
			ballRadius,
			linear_damp,
			angular_damp,
			ball_friction_value,
			floor_friction,
			ball_bounce_value,
			floor_bounce,
			gravity_scale,
			global_position.y)
		
		if Input.is_action_just_released("ui_accept"): # release space
			hit_ball()
		# queue_redraw() # for debug draw
			
# debug drawing
func _draw():
	if isAiming and aimDirection != Vector3.ZERO:
		# add power bar and aim indicator here
		pass

func start_aiming():
	isAiming = true
	aimPower = 0.0
	powerMeterUI.show_meter()
	trajectoryDrawer.show_trajectory()
	
func update_aim(delta):
	# get aim direction from camera forward
	if camera:
		aimDirection = -camera.global_transform.basis.z
		aimDirection.y = 0.5
		aimDirection = aimDirection.normalized()
		
	# increase power while holding
	aimPower += delta * s_chargeRate
	aimPower = clamp(aimPower, 0.0, s_maxPower )
	
	powerMeterUI.update_power(aimPower, s_maxPower)
	
func hit_ball():
	if aimDirection != Vector3.ZERO:
		# apply impulse to the ball
		var hitForce = aimDirection * aimPower
		apply_central_impulse(hitForce)
	
	isAiming = false
	aimPower = 0.0
	powerMeterUI.hide_meter()
	trajectoryDrawer.hide_trajectory()
	
func is_at_rest() -> bool:
	return linear_velocity.length() < 0.1
	
