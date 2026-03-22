class_name PhysicsSimulator
extends Object

# Physics state
class SimulationState:
	var position: Vector3
	var velocity: Vector3
	var time: float
	var is_on_ground: bool

	func _init(pos: Vector3 = Vector3.ZERO, vel: Vector3 = Vector3.ZERO) -> void:
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
	## TerrainData for terrain-aware physics. Null = flat ground.
	var terrain: RefCounted  # TerrainData
	var wind: Vector3

	func _init() -> void:
		mass = 0.045
		ball_radius = 0.02
		linear_damp = 1.5
		angular_damp = 2.5
		ball_friction = 1.0
		ground_friction = 0.4
		ball_bounce = 0.6
		ground_bounce = 0.3
		gravity_scale = 1.0
		ground_height = 0.0
		terrain = null
		wind = Vector3.ZERO

# Step the simulation forward by delta time
static func simulate_step(state: SimulationState, params: PhysicsParams, delta: float) -> SimulationState:
	var new_state: SimulationState = SimulationState.new(state.position, state.velocity)
	new_state.time = state.time + delta

	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var gravity_vector := Vector3(0.0, -gravity * params.gravity_scale, 0.0)

	new_state.velocity += gravity_vector * delta

	# Wind — only affects airborne ball
	if params.wind.length_squared() > 0.0 and not state.is_on_ground:
		new_state.velocity += params.wind * delta

	var damping_factor := 1.0 / (1.0 + params.linear_damp * delta)
	new_state.velocity *= damping_factor

	new_state.position += new_state.velocity * delta

	# Terrain-aware ground height (falls back to flat ground_height when no terrain)
	var ground_h: float = params.ground_height
	if params.terrain:
		ground_h = params.terrain.get_height_at(
			new_state.position.x, new_state.position.z
		)

	if new_state.position.y <= ground_h + params.ball_radius:
		new_state.position.y = ground_h + params.ball_radius

		# Terrain normal (flat ground = straight up)
		var ground_normal := Vector3.UP
		if params.terrain:
			ground_normal = params.terrain.get_normal_at(
				new_state.position.x, new_state.position.z
			)

		var was_on_ground: bool = state.is_on_ground
		new_state.is_on_ground = true

		if not was_on_ground and new_state.velocity.y < 0.0:
			# First impact — bounce off the surface normal (not just Y)
			var vel_into_surface: float = -new_state.velocity.dot(ground_normal)
			if vel_into_surface > 0.0:
				var combined_bounce := params.ball_bounce * params.ground_bounce
				new_state.velocity += ground_normal * vel_into_surface * (1.0 + combined_bounce)
				# Kill tiny bounces so the ball settles
				if new_state.velocity.dot(ground_normal) < 0.5:
					# Remove velocity component into the surface, keep tangent
					var normal_comp: float = new_state.velocity.dot(ground_normal)
					if normal_comp < 0.0:
						new_state.velocity -= ground_normal * normal_comp
		else:
			# Already on the ground — constrain velocity to the surface plane.
			# Remove the component going into the surface so the ball slides
			# along it instead of micro-bouncing every frame.
			var normal_comp: float = new_state.velocity.dot(ground_normal)
			if normal_comp < 0.0:
				new_state.velocity -= ground_normal * normal_comp

		# Apply slope force and friction while on the surface
		# Project gravity onto slope to accelerate ball downhill
		var slope_force: Vector3 = gravity_vector - ground_normal * gravity_vector.dot(ground_normal)

		# Compute friction parameters up front
		var zone_friction: float = params.ground_friction
		if params.terrain:
			zone_friction = params.terrain.get_friction_at(
				new_state.position.x, new_state.position.z,
			)
		var combined_friction := params.ball_friction * zone_friction
		var normal_force: float = ground_normal.y
		var friction_accel: float = (
			combined_friction * gravity * params.gravity_scale * normal_force
		)

		var horizontal_velocity := Vector3(new_state.velocity.x, 0.0, new_state.velocity.z)
		var horizontal_speed := horizontal_velocity.length()
		var slope_horizontal := Vector3(slope_force.x, 0.0, slope_force.z)
		var slope_accel := slope_horizontal.length()

		if horizontal_speed < 0.1:
			# Low speed — static friction model.
			# Ball only moves if slope force exceeds friction threshold.
			if slope_accel > friction_accel and slope_accel > 0.001:
				var net_accel := slope_accel - friction_accel
				var downhill_dir := slope_horizontal.normalized()
				new_state.velocity.x += downhill_dir.x * net_accel * delta
				new_state.velocity.z += downhill_dir.z * net_accel * delta
			else:
				new_state.velocity.x = 0.0
				new_state.velocity.z = 0.0
		else:
			# Moving — apply slope force then kinetic friction
			new_state.velocity += slope_force * delta
			horizontal_velocity = Vector3(new_state.velocity.x, 0.0, new_state.velocity.z)
			horizontal_speed = horizontal_velocity.length()

			if horizontal_speed > 0.001:
				var friction_force := (
					-horizontal_velocity.normalized() * friction_accel * delta
				)
				var new_horizontal := horizontal_velocity + friction_force

				if new_horizontal.dot(horizontal_velocity) > 0.0:
					new_state.velocity.x = new_horizontal.x
					new_state.velocity.z = new_horizontal.z
				else:
					# Friction would stop the ball — check slope vs static friction
					if slope_accel > friction_accel:
						var net_accel := slope_accel - friction_accel
						var downhill_dir := slope_horizontal.normalized()
						new_state.velocity.x = downhill_dir.x * net_accel * delta
						new_state.velocity.z = downhill_dir.z * net_accel * delta
					else:
						new_state.velocity.x = 0.0
						new_state.velocity.z = 0.0
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
	var state: SimulationState = SimulationState.new(start_position, initial_velocity)

	var num_steps: int = int(max_time / time_step)

	for _i: int in range(num_steps):
		positions.append(state.position)

		state = simulate_step(state, params, time_step)

		if state.velocity.length() < stop_threshold:
			positions.append(state.position)
			break

		if state.position.distance_to(start_position) > 2000.0:
			break

	return positions

# Check if simulation has stopped.
# On the ground, use a higher threshold for horizontal speed so the ball
# doesn't creep along at near-zero speed. But on slopes, require the slope
# force to be negligible before stopping — otherwise the ball should roll.
static func is_stopped(state: SimulationState, threshold: float = 0.1, params: PhysicsParams = null) -> bool:
	if state.is_on_ground:
		var horizontal_speed: float = Vector2(state.velocity.x, state.velocity.z).length()
		if horizontal_speed >= threshold * 4.0:
			return false

		# Check if slope would keep the ball rolling
		if params and params.terrain:
			var ground_normal: Vector3 = params.terrain.get_normal_at(
				state.position.x, state.position.z
			)
			# Slope steepness: 1.0 = flat, <1.0 = sloped
			var steepness: float = ground_normal.y
			if steepness < 0.98:
				# On a slope — compute whether slope force exceeds friction
				var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
				var gravity_vector := Vector3(0.0, -gravity * params.gravity_scale, 0.0)
				var slope_force: Vector3 = gravity_vector - ground_normal * gravity_vector.dot(ground_normal)
				var zone_friction: float = params.terrain.get_friction_at(
					state.position.x, state.position.z
				)
				var normal_force: float = ground_normal.y
				var friction_mag: float = params.ball_friction * zone_friction * gravity * params.gravity_scale * normal_force
				# If slope force can overcome friction, ball should keep rolling
				if slope_force.length() > friction_mag:
					return false
		return true
	return state.velocity.length() < threshold
