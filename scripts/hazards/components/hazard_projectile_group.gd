## HazardProjectileGroup — manages a group of animated projectiles
## (boulders, fireballs, debris) that travel along a direction.
##
## Used by RockSlideHazard and similar moving-collider hazards.
class_name HazardProjectileGroup
extends Node3D

var _projectiles: Array[MeshInstance3D] = []
var _speeds: Array[float] = []
var _offsets: Array[float] = []
var _count: int = 3
var _speed_variance: float = 0.15
var _stagger: float = 0.3
var _travel_distance: float = 30.0
var _bob_amplitude: float = 0.2
var _spin_speed: float = 4.0


func setup(
	projectile_mesh: Mesh,
	mat: Material,
	count: int = 3,
	speed_variance: float = 0.15,
	stagger: float = 0.3,
	travel_distance: float = 30.0,
	bob_amplitude: float = 0.2,
	spin_speed: float = 4.0,
) -> void:
	_count = count
	_speed_variance = speed_variance
	_stagger = stagger
	_travel_distance = travel_distance
	_bob_amplitude = bob_amplitude
	_spin_speed = spin_speed

	for i: int in range(_count):
		var mi := MeshInstance3D.new()
		mi.mesh = projectile_mesh
		mi.material_override = mat
		mi.visible = false
		add_child(mi)
		_projectiles.append(mi)
		_speeds.append(1.0 + float(i) * _speed_variance)
		_offsets.append(float(i) * _stagger)


func show_projectiles() -> void:
	for mi: MeshInstance3D in _projectiles:
		mi.visible = true


func hide_projectiles() -> void:
	for mi: MeshInstance3D in _projectiles:
		mi.visible = false


## Animate all projectiles along `direction` based on elapsed active time.
func animate(
	active_time: float,
	duration: float,
	direction: Vector3,
	delta: float,
) -> void:
	var half_dist: float = _travel_distance * 0.5
	for i: int in range(_projectiles.size()):
		var t: float = (active_time - _offsets[i]) \
			* _speeds[i] / duration
		t = clampf(t, 0.0, 1.0)
		var pos: Vector3 = direction * lerpf(-half_dist, half_dist, t)
		pos.y = 0.8 + sin(t * 12.0) * _bob_amplitude
		_projectiles[i].position = pos
		_projectiles[i].rotate_x(delta * _spin_speed)


## Return world positions of all visible projectiles (for proximity collision).
func get_projectile_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for mi: MeshInstance3D in _projectiles:
		if mi.visible:
			positions.append(mi.global_position)
	return positions
