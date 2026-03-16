## BallTrail — velocity-based ribbon trail behind the golf ball.
##
## Stores recent positions in a ring buffer and draws a triangle strip
## that tapers in width and fades in alpha from tail to head.
class_name BallTrail
extends Node3D

const MAX_POINTS: int = 40
const BASE_WIDTH: float = 0.12
const MIN_VELOCITY: float = 1.0

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _points: Array[Vector3] = []
var _active: bool = false


func _ready() -> void:
	top_level = true
	global_position = Vector3.ZERO
	_setup_mesh()


func _setup_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true


func start() -> void:
	_active = true
	_points.clear()
	_mesh.clear_surfaces()


func stop() -> void:
	_active = false
	_points.clear()
	_mesh.clear_surfaces()


func add_point(pos: Vector3, velocity: Vector3) -> void:
	if not _active:
		return
	var speed: float = velocity.length()
	if speed < MIN_VELOCITY:
		# Still trim old points so trail shrinks when slowing down
		if _points.size() > 0:
			_points.remove_at(0)
			_draw(speed)
		return
	_points.append(pos)
	if _points.size() > MAX_POINTS:
		_points.remove_at(0)
	_draw(speed)


func _draw(speed: float) -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return

	# Scale width by speed (capped)
	var speed_factor: float = clampf(speed / 15.0, 0.3, 1.0)

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)

	var count: int = _points.size()
	for i: int in range(count):
		var pos: Vector3 = _points[i]
		# t: 0.0 = oldest (tail), 1.0 = newest (head)
		var t: float = float(i) / float(count - 1)

		# Direction for perpendicular offset
		var forward: Vector3
		if i < count - 1:
			forward = (_points[i + 1] - pos).normalized()
		else:
			forward = (pos - _points[i - 1]).normalized()

		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		if right.length_squared() < 0.01:
			right = Vector3.RIGHT

		# Width tapers: thin at tail, full at head
		var half_w: float = BASE_WIDTH * t * speed_factor

		# Alpha fades: transparent at tail, opaque at head
		var alpha: float = t * 0.6

		var color := Color(1.0, 1.0, 1.0, alpha)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(pos + right * half_w)
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(pos - right * half_w)

	_mesh.surface_end()
