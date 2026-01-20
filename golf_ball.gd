extends RigidBody3D

# aiming dynamic variables
var is_aiming = false
var aim_direction = Vector3.ZERO
var aim_power = 0.0

var stop_velocity_threshold = 0.3

# Simulated physics state
var is_simulating = false
var sim_state: PhysicsSimulator.SimulationState
var sim_params: PhysicsSimulator.PhysicsParams

@export var s_maxPower = 2
@export var s_chargeRate = .2

# camera reference
@onready var camera = get_viewport().get_camera_3d()

# node references
@export var powerMeterUI: ProgressBar
@export var floorNode: StaticBody3D

@onready var trajectoryDrawer: TrajectoryDrawer

var scoring_manager: ScoringManager

func _ready():
	contact_monitor = true
	max_contacts_reported = 4

	# "ball" group is used for cup collision
	add_to_group("ball")
	
	trajectoryDrawer = TrajectoryDrawer.new()
	add_child(trajectoryDrawer)
	
	scoring_manager = get_node("/root/Main/ScoringManager")
	
	#initialize physics parameters (used by trajectory line and simulating)
	setup_physics_params()
	
	# In order to keep some physics (collision detection with obstacles)
	# set freeze mode and use move_and_collide instead of setting global_position
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				
func setup_physics_params():
	sim_params = PhysicsSimulator.PhysicsParams.new()
	sim_params.mass = mass
	
	sim_params.linear_damp = linear_damp
	sim_params.angular_damp = angular_damp
	sim_params.gravity_scale = gravity_scale
	sim_params.ground_height = 0.0
	
	# find collision shape to get radius
	sim_params.ball_radius = 0.0
	for child in get_children():
		if child is CollisionShape3D:
			if child.shape is Shape3D:
				sim_params.ball_radius = child.shape.radius
				break
	
	# Get ball physics material
	if physics_material_override:
		sim_params.ball_friction = physics_material_override.friction
		sim_params.ball_bounce = physics_material_override.bounce
		
	# Find the floor and get its physics material
	if floorNode.physics_material_override:
		sim_params.ground_friction = floorNode.physics_material_override.friction
		sim_params.ground_bounce = floorNode.physics_material_override.bounce
		
func _physics_process(delta):
	if is_simulating:
		simulate_physics(delta)
		
func simulate_physics(delta):
	# Use shared physics simulator
	sim_state = PhysicsSimulator.simulate_step(sim_state, sim_params, delta)
	
	# Update ball position
	# global_position = sim_state.position
	move_and_collide(sim_state.velocity * delta)
	
	# Check if stopped
	if PhysicsSimulator.is_stopped(sim_state, stop_velocity_threshold):
		is_simulating = false
		freeze = false
	
func _process(delta):
	if is_at_rest() and not is_aiming:
		# ball has stopped, ready to aim
		if Input.is_action_just_pressed("ui_accept"): # Space bar
			start_aiming()
	if is_aiming:
		update_aim(delta)
		
		# Position trajectory at ball
		trajectoryDrawer.global_position = global_position
		
		var hit_impulse = aim_direction * aim_power
		
		trajectoryDrawer.draw_trajectory(sim_params, hit_impulse)
		
		if Input.is_action_just_released("ui_accept"): # release space
			hit_ball()
		# queue_redraw() # for debug draw
			
# debug drawing
func _draw():
	if is_aiming and aim_direction != Vector3.ZERO:
		# add power bar and aim indicator here
		pass

func start_aiming():
	is_aiming = true
	aim_power = 0.0
	powerMeterUI.show_meter()
	trajectoryDrawer.show_trajectory()
	
func update_aim(delta):
	# get aim direction from camera forward
	if camera:
		aim_direction = -camera.global_transform.basis.z
		aim_direction.y = 0.5
		aim_direction = aim_direction.normalized()
		
	# increase power while holding
	aim_power += delta * s_chargeRate
	aim_power = clamp(aim_power, 0.0, s_maxPower )
	
	powerMeterUI.update_power(aim_power, s_maxPower)
	
func hit_ball():
	if aim_direction != Vector3.ZERO:
		# Start simulation with shared physics
		var hit_impulse = aim_direction * aim_power
		var initial_velocity = hit_impulse / mass
		
		sim_state = PhysicsSimulator.SimulationState.new(global_position, initial_velocity)
		is_simulating = true
		freeze = true # Freeze RigidBody physics
		
		# add stroke to counter
		if scoring_manager:
			scoring_manager.add_stroke()
	
	is_aiming = false
	aim_power = 0.0
	powerMeterUI.hide_meter()
	trajectoryDrawer.hide_trajectory()
	
func is_at_rest() -> bool:
	return not is_simulating and linear_velocity.length() < 0.1
	
