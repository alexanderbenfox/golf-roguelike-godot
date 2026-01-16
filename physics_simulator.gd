class_name PhysicsSimulator
extends Object

# Physics state
class SimulationState:
	var position: Vector3
	var velocity: Vector3
	var time: float
	var is_on_ground: bool
	
	func _init(pos: Vector3 = Vector3.ZERO, vel: Vector3 = Vector3.ZERO):
		position = pos
		velocity = vel
		time = 0.0
		is_on_ground = false

# Physics parameters
class PhysicsParams:
	var mass: float
	var ball_radius: float
	var linear_damp: float
	var angular_damp: float
	var ball_friction: float
	var ground_friction: float
	var ball_bounce: float
	var ground_bounce: float
	var gravity_scale: float
	var ground_height: float
	
	func _init():
		mass = 0.045
		ball_radius = 0.02
		linear_damp = 1.5
		angular_damp = 2.5
		ball_friction = 1.0
		ground_friction = 2.0
		ball_bounce = 0.6
		ground_bounce = 0.3
		gravity_scale = 1.0
		ground_height = 0.0

# Step the simulation forward by delta time
static func simulate_step(state: SimulationState, params: PhysicsParams, delta: float) -> SimulationState:
	var new_state = SimulationState.new(state.position, state.velocity)
	new_state.time = state.time + delta
	
	# Get gravity
	var gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var gravity_vector = Vector3(0, -gravity * params.gravity_scale, 0)
	
	# Apply gravity
	new_state.velocity += gravity_vector * delta
	
	# Apply linear damping (air resistance)
	var damping_factor = 1.0 / (1.0 + params.linear_damp * delta)
	new_state.velocity *= damping_factor
	
	# Update position
	new_state.position += new_state.velocity * delta
	
	# Check ground collision
	if new_state.position.y <= params.ground_height + params.ball_radius:
		new_state.is_on_ground = true
		new_state.position.y = params.ground_height + params.ball_radius
		
		# Apply bounce
		if new_state.velocity.y < 0:
			var combined_bounce = params.ball_bounce * params.ground_bounce
			new_state.velocity.y = -new_state.velocity.y * combined_bounce
			
			# If bounce is tiny, start rolling
			if abs(new_state.velocity.y) < 0.5:
				new_state.velocity.y = 0
		
		# Apply rolling friction when on ground
		if new_state.position.y <= params.ground_height + params.ball_radius + 0.01:
			var horizontal_velocity = Vector3(new_state.velocity.x, 0, new_state.velocity.z)
			
			if horizontal_velocity.length() > 0.01:
				var combined_friction = params.ball_friction * params.ground_friction
				var friction_force = -horizontal_velocity.normalized() * combined_friction * gravity * delta
				
				var new_horizontal = horizontal_velocity + friction_force
				
				# Don't reverse direction
				if new_horizontal.dot(horizontal_velocity) > 0:
					new_state.velocity.x = new_horizontal.x
					new_state.velocity.z = new_horizontal.z
				else:
					new_state.velocity.x = 0
					new_state.velocity.z = 0
	else:
		new_state.is_on_ground = false
	
	return new_state

# Simulate full trajectory and return array of positions
static func simulate_trajectory(
	initial_velocity: Vector3, 
	params: PhysicsParams,
	start_position: Vector3 = Vector3.ZERO,
	time_step: float = 0.05,
	max_time: float = 10.0,
	stop_threshold: float = 0.1
) -> Array[Vector3]:
	
	var positions: Array[Vector3] = []
	var state = SimulationState.new(start_position, initial_velocity)
	
	var num_steps = int(max_time / time_step)
	
	for i in range(num_steps):
		positions.append(state.position)
		
		state = simulate_step(state, params, time_step)
		
		# Stop if velocity is very low
		if state.velocity.length() < stop_threshold:
			positions.append(state.position)
			break
		
		# Stop if trajectory goes too far
		if state.position.length() > 200.0:
			break
	
	return positions

# Check if simulation has stopped
static func is_stopped(state: SimulationState, threshold: float = 0.1) -> bool:
	return state.velocity.length() < threshold
