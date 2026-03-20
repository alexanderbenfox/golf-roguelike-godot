## RockSlideHazard — canyon hazard where boulders periodically roll
## across the fairway perpendicular to the hole direction.
##
## Visual states:
##   IDLE:    orange warning disc on the ground marking the slide path
##   WARNING: disc pulses, dust particles start at the origin side
##   ACTIVE:  boulders animate across the fairway, Area3D enabled
class_name RockSlideHazard
extends DynamicHazardBase

const BOULDER_COUNT: int = 3
const SLIDE_DISTANCE: float = 30.0  # how far boulders travel
const BOULDER_HIT_RADIUS: float = 2.0  # how close a boulder must be to hit the ball

var _ground_disc: MeshInstance3D
var _disc_material: StandardMaterial3D
var _boulders: Array[MeshInstance3D] = []
var _boulder_speeds: Array[float] = []
var _boulder_offsets: Array[float] = []  # stagger along slide path timing
var _warning_time: float = 0.0
var _active_time: float = 0.0
var _hit_bodies: Dictionary = {}  # tracks bodies already hit this active cycle


func _build_visuals() -> void:
	# Ground warning strip — elongated disc along the slide path
	_ground_disc = MeshInstance3D.new()
	var disc := BoxMesh.new()
	disc.size = Vector3(effect_radius * 2.0, 0.05, 3.0)
	_ground_disc.mesh = disc

	_disc_material = StandardMaterial3D.new()
	_disc_material.albedo_color = Color(0.8, 0.45, 0.15, 0.5)
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ground_disc.material_override = _disc_material

	# Orient the strip along the slide direction
	if slide_direction.length_squared() > 0.01:
		_ground_disc.look_at_from_position(
			Vector3.ZERO,
			slide_direction,
			Vector3.UP,
		)
	_ground_disc.position.y = 0.03
	add_child(_ground_disc)

	# Create boulder meshes (hidden until active)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.35, 0.25)

	for i: int in range(BOULDER_COUNT):
		var boulder := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.6 + float(i) * 0.2
		sphere.height = sphere.radius * 2.0
		boulder.mesh = sphere
		boulder.material_override = rock_mat
		boulder.visible = false
		add_child(boulder)
		_boulders.append(boulder)
		_boulder_speeds.append(1.0 + float(i) * 0.15)
		_boulder_offsets.append(float(i) * 0.3)


func _on_enter_idle() -> void:
	_disc_material.albedo_color = Color(0.8, 0.45, 0.15, 0.5)
	_warning_time = 0.0
	_active_time = 0.0
	for boulder: MeshInstance3D in _boulders:
		boulder.visible = false


func _on_enter_warning() -> void:
	_warning_time = 0.0
	for boulder: MeshInstance3D in _boulders:
		boulder.visible = false


func _on_enter_active() -> void:
	_active_time = 0.0
	_hit_bodies.clear()
	_disc_material.albedo_color = Color(0.9, 0.35, 0.10, 0.7)
	for boulder: MeshInstance3D in _boulders:
		boulder.visible = true


## Override base class — don't trigger on area entry alone.
## Instead we check boulder proximity each frame in _update_visuals.
func _on_body_entered(_body: Node3D) -> void:
	pass


func _update_visuals(delta: float, current_state: State, _phase: float) -> void:
	if current_state == State.WARNING:
		_warning_time += delta
		var pulse: float = 0.5 + 0.5 * sin(_warning_time * 8.0)
		_disc_material.albedo_color = Color(
			lerpf(0.8, 1.0, pulse),
			lerpf(0.45, 0.30, pulse),
			lerpf(0.15, 0.05, pulse),
			lerpf(0.5, 0.8, pulse),
		)
	elif current_state == State.ACTIVE:
		_active_time += delta
		# Animate boulders along the slide direction
		var half_dist: float = SLIDE_DISTANCE * 0.5
		for i: int in range(_boulders.size()):
			var t: float = (_active_time - _boulder_offsets[i]) \
				* _boulder_speeds[i] / active_duration
			t = clampf(t, 0.0, 1.0)
			var pos: Vector3 = slide_direction * lerpf(
				-half_dist, half_dist, t,
			)
			# Bob slightly up and down for rolling feel
			pos.y = 0.8 + sin(t * 12.0) * 0.2
			_boulders[i].position = pos
			# Spin the boulder
			_boulders[i].rotate_x(delta * 4.0)

		# Check if any boulder is close enough to hit a ball
		for body: Node3D in _area.get_overlapping_bodies():
			if body.get_instance_id() in _hit_bodies:
				continue
			var body_pos: Vector3 = body.global_position
			for boulder: MeshInstance3D in _boulders:
				if not boulder.visible:
					continue
				var boulder_world: Vector3 = boulder.global_position
				var dist: float = body_pos.distance_to(boulder_world)
				if dist < BOULDER_HIT_RADIUS:
					_hit_bodies[body.get_instance_id()] = true
					var impulse := _compute_impulse(body_pos)
					hazard_activated.emit(impulse)
					break


func _compute_impulse(ball_pos: Vector3) -> Vector3:
	# Knock ball in the slide direction + upward
	return slide_direction * intensity + Vector3.UP * intensity * 0.5
