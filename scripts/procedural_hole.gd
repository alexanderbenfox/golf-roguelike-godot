## ProceduralHole — builds the full 3D hole scene from a HoleLayout.
##
## Responsibilities:
##   - Fairway, green, and tee-box surface meshes
##   - Tree obstacles (StaticBody3D with collision so ball bounces off)
##   - Bunker visuals (sand-coloured disc; friction penalty is a future TODO)
##   - Cup + flag (owns the Area3D and emits ball_entered_cup)
##
## Usage:
##   var hole = ProceduralHole.new()
##   add_child(hole)
##   hole.build(layout)   ← call AFTER add_child so global transforms are valid
class_name ProceduralHole
extends Node3D

signal ball_entered_cup

const FAIRWAY_COLOR  := Color(0.20, 0.55, 0.15)
const GREEN_COLOR    := Color(0.15, 0.65, 0.15)
const TEE_COLOR      := Color(0.85, 0.85, 0.85)
const ROUGH_EDGE_COLOR := Color(0.30, 0.48, 0.12)
const TRUNK_COLOR    := Color(0.35, 0.20, 0.05)
const FOLIAGE_COLOR  := Color(0.10, 0.38, 0.08)
const SAND_COLOR     := Color(0.85, 0.78, 0.50)
const FLAG_COLOR     := Color(0.90, 0.10, 0.10)

const GREEN_RADIUS   := 8.0
const CUP_RADIUS     := 0.4
const CUP_HEIGHT     := 0.4

var layout: HoleGenerator.HoleLayout
var _cup_area: Area3D


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

func build(hole_layout: HoleGenerator.HoleLayout) -> void:
	layout = hole_layout
	_build_terrain()
	_build_obstacles()
	_build_cup()


func get_tee_world_position() -> Vector3:
	# Tee is always at the hole's scene origin, 1 unit above ground for ball spawn
	return global_position + Vector3(0.0, 1.0, 0.0)


# -------------------------------------------------------------------------
# Terrain surfaces
# -------------------------------------------------------------------------

func _build_terrain() -> void:
	var dir   := Vector3(sin(layout.hole_direction), 0.0, -cos(layout.hole_direction))
	var cup_flat := Vector3(layout.cup_position.x, 0.0, layout.cup_position.z)

	# Ground collision — wide flat box covering the whole hole so the ball never falls through.
	# Extends well beyond the fairway on all sides to cover errant shots.
	var ground_body := StaticBody3D.new()
	var ground_col := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	var ground_width := layout.fairway_width + 60.0   # wide margin either side
	var ground_len   := layout.hole_length + 40.0     # margin behind tee and past cup
	ground_shape.size = Vector3(ground_width, 1.0, ground_len)
	ground_col.shape = ground_shape
	ground_body.add_child(ground_col)
	# Centre the box under the hole midpoint; top face sits at y = 0.5
	ground_body.position = dir * (layout.hole_length * 0.5) + Vector3(0.0, -0.5, 0.0)
	ground_body.rotation.y = layout.hole_direction
	add_child(ground_body)

	# Fairway — rectangle from tee to cup aligned with hole direction
	_add_plane_mesh(
		dir * (layout.hole_length * 0.5),   # midpoint
		Vector2(layout.fairway_width, layout.hole_length),
		layout.hole_direction,
		FAIRWAY_COLOR,
		0.01
	)

	# Green — disc around the cup
	_add_disc_mesh(cup_flat, GREEN_RADIUS, GREEN_COLOR, 0.012)

	# Tee box — small square at origin
	_add_plane_mesh(Vector3.ZERO, Vector2(4.0, 4.0), 0.0, TEE_COLOR, 0.015)


## Adds a PlaneMesh child at `center`, rotated `angle` around Y.
func _add_plane_mesh(center: Vector3, size: Vector2, angle: float, color: Color, y_offset: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _flat_material(color)
	mi.position = center + Vector3(0.0, y_offset, 0.0)
	mi.rotation.y = angle
	add_child(mi)


## Adds a flat CylinderMesh disc (for circular areas like the green).
func _add_disc_mesh(center: Vector3, radius: float, color: Color, y_offset: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mi.mesh = mesh
	mi.material_override = _flat_material(color)
	mi.position = center + Vector3(0.0, y_offset, 0.0)
	add_child(mi)


# -------------------------------------------------------------------------
# Obstacles
# -------------------------------------------------------------------------

func _build_obstacles() -> void:
	for obs: HoleGenerator.ObstacleDescriptor in layout.obstacles:
		match obs.type:
			HoleGenerator.ObstacleDescriptor.Type.TREE:
				_build_tree(obs)
			HoleGenerator.ObstacleDescriptor.Type.BUNKER:
				_build_bunker(obs)


func _build_tree(obs: HoleGenerator.ObstacleDescriptor) -> void:
	var body := StaticBody3D.new()

	# Collision — single cylinder covers trunk + canopy
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = obs.radius
	shape.height = obs.height
	col.shape = shape
	body.add_child(col)

	# Trunk visual
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius    = obs.radius * 0.30
	trunk_mesh.bottom_radius = obs.radius * 0.40
	trunk_mesh.height        = obs.height * 0.40
	trunk.mesh = trunk_mesh
	trunk.material_override = _flat_material(TRUNK_COLOR)
	trunk.position = Vector3(0.0, -obs.height * 0.30, 0.0)  # relative to body centre
	body.add_child(trunk)

	# Foliage visual (cone-like cylinder)
	var foliage := MeshInstance3D.new()
	var foliage_mesh := CylinderMesh.new()
	foliage_mesh.top_radius    = 0.05
	foliage_mesh.bottom_radius = obs.radius * 1.8
	foliage_mesh.height        = obs.height * 0.65
	foliage.mesh = foliage_mesh
	foliage.material_override = _flat_material(FOLIAGE_COLOR)
	foliage.position = Vector3(0.0, obs.height * 0.08, 0.0)
	body.add_child(foliage)

	# Place body so its centre is at mid-height of the tree
	body.position = obs.world_position + Vector3(0.0, obs.height * 0.5, 0.0)
	add_child(body)


func _build_bunker(obs: HoleGenerator.ObstacleDescriptor) -> void:
	_add_disc_mesh(
		Vector3(obs.world_position.x, 0.0, obs.world_position.z),
		obs.radius,
		SAND_COLOR,
		0.013
	)


# -------------------------------------------------------------------------
# Cup + flag
# -------------------------------------------------------------------------

func _build_cup() -> void:
	_cup_area = Area3D.new()
	_cup_area.name = "Cup"
	add_child(_cup_area)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = CUP_RADIUS
	shape.height = CUP_HEIGHT
	col.shape = shape
	_cup_area.add_child(col)

	_cup_area.global_position = layout.cup_position
	_cup_area.body_entered.connect(_on_body_entered_cup)

	_build_cup_visual()


func _build_cup_visual() -> void:
	# Black hole cylinder
	var hole := MeshInstance3D.new()
	var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius    = CUP_RADIUS
	hole_mesh.bottom_radius = CUP_RADIUS
	hole_mesh.height        = CUP_HEIGHT
	hole.mesh = hole_mesh
	hole.material_override = _flat_material(Color.BLACK)
	_cup_area.add_child(hole)

	# Flag pole
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius    = 0.02
	pole_mesh.bottom_radius = 0.02
	pole_mesh.height        = 2.0
	pole.mesh = pole_mesh
	pole.material_override = _flat_material(Color.WHITE)
	pole.position = Vector3(0.0, 1.0, 0.0)
	_cup_area.add_child(pole)

	# Flag
	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.5, 0.3, 0.02)
	flag.mesh = flag_mesh
	flag.material_override = _flat_material(FLAG_COLOR)
	flag.position = Vector3(0.25, 1.85, 0.0)
	_cup_area.add_child(flag)


func _on_body_entered_cup(body: Node3D) -> void:
	if body.is_in_group("ball"):
		ball_entered_cup.emit()


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
