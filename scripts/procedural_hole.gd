## ProceduralHole — builds the full 3D hole scene from a HoleLayout.
##
## Responsibilities:
##   - Terrain mesh (vertex-coloured heightmap) with collision
##   - Tree obstacles (StaticBody3D with collision so ball bounces off)
##   - Bunkers (terrain-integrated — painted as BUNKER zones with bowl depressions)
##   - Cup + flag (owns the Area3D and emits ball_entered_cup)
##
## Usage:
##   var hole = ProceduralHole.new()
##   add_child(hole)
##   hole.build(layout)   ← call AFTER add_child so global transforms are valid
class_name ProceduralHole
extends Node3D

signal ball_entered_cup
signal ball_hit_dynamic_hazard(impulse: Vector3)

const TerrainMeshBuilderScript = preload("res://scripts/terrain/terrain_mesh_builder.gd")

const TRUNK_COLOR    := Color(0.35, 0.20, 0.05)
const FOLIAGE_COLOR  := Color(0.10, 0.38, 0.08)
const FLAG_COLOR     := Color(0.90, 0.10, 0.10)

const GREEN_RADIUS   := 8.0
const CUP_RADIUS     := 0.4
const CUP_HEIGHT     := 0.4

var layout: HoleGenerator.HoleLayout
var _cup_area: Area3D

## Optional hazard modifier stack — set before calling build().
## When set, modifies hazard descriptor values (intensity, timing, etc.)
## before each hazard is instantiated.
var hazard_modifier_stack: RefCounted  # HazardModifierStack

# Bounds for OOB detection — set during _build_terrain()
var _bounds_center: Vector3      # local offset from node origin (XZ plane)
var _bounds_half_width: float    # perpendicular to hole direction
var _bounds_half_length: float   # along hole direction
var _bounds_angle: float         # radians, matches hole_direction


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

func build(hole_layout: HoleGenerator.HoleLayout) -> void:
	layout = hole_layout
	_build_terrain()
	_build_hazard_planes()
	_build_obstacles()
	_build_dynamic_hazards()
	_build_cup()


func get_tee_world_position() -> Vector3:
	if layout.terrain_data:
		var terrain_y: float = layout.terrain_data.get_height_at(0.0, 0.0)
		return global_position + Vector3(0.0, terrain_y + 0.2, 0.0)
	return global_position + Vector3(0.0, 0.7, 0.0)


## Returns true if `world_pos` is outside the playable area for this hole.
func is_out_of_bounds(world_pos: Vector3) -> bool:
	# Well below lowest possible terrain
	if world_pos.y < -10.0:
		return true

	# Transform world position into the hole's rotated local coordinate system
	var relative: Vector3 = world_pos - global_position - _bounds_center
	var cos_a: float = cos(-_bounds_angle)
	var sin_a: float = sin(-_bounds_angle)
	var local_x: float = relative.x * cos_a - relative.z * sin_a
	var local_z: float = relative.x * sin_a + relative.z * cos_a

	return absf(local_x) > _bounds_half_width or absf(local_z) > _bounds_half_length


# -------------------------------------------------------------------------
# Terrain mesh
# -------------------------------------------------------------------------

func _build_terrain() -> void:
	var dir := Vector3(sin(layout.hole_direction), 0.0, -cos(layout.hole_direction))

	# OOB bounds (same dimensions as before)
	var ground_width: float = layout.fairway_width + 60.0
	var ground_len: float = layout.hole_length + 40.0
	_bounds_center = dir * (layout.hole_length * 0.5)
	_bounds_half_width = ground_width * 0.5
	_bounds_half_length = ground_len * 0.5
	_bounds_angle = layout.hole_direction

	if not layout.terrain_data:
		return

	# Build mesh + collision from heightmap
	var result: Dictionary = TerrainMeshBuilderScript.build(
		layout.terrain_data
	)
	var biome: RefCounted = layout.terrain_data.biome

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = result["mesh"] as ArrayMesh
	mesh_instance.material_override = \
		TerrainMeshBuilderScript.create_material(biome)
	add_child(mesh_instance)

	var static_body := StaticBody3D.new()
	var col_shape := CollisionShape3D.new()
	col_shape.shape = result["shape"] as ConcavePolygonShape3D
	static_body.add_child(col_shape)
	add_child(static_body)


# -------------------------------------------------------------------------
# Hazard planes (water / lava)
# -------------------------------------------------------------------------

func _build_hazard_planes() -> void:
	if not layout.terrain_data:
		return
	var terrain: RefCounted = layout.terrain_data
	var w: float = terrain.grid_width * terrain.cell_size
	var d: float = terrain.grid_depth * terrain.cell_size
	var cx: float = terrain.origin.x + w * 0.5
	var cz: float = terrain.origin.z + d * 0.5

	if terrain.water_height > -900.0:
		_add_hazard_plane(
			Vector3(cx, terrain.water_height + 0.05, cz),
			Vector2(w, d),
			Color(0.1, 0.3, 0.65, 0.55),
			false,
		)
	if terrain.lava_height > -900.0:
		_add_hazard_plane(
			Vector3(cx, terrain.lava_height + 0.05, cz),
			Vector2(w, d),
			Color(0.9, 0.25, 0.02, 0.7),
			true,
		)


func _add_hazard_plane(
	center: Vector3, size: Vector2, color: Color, emissive: bool,
) -> void:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	mi.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emissive:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 1.5
	mi.material_override = mat
	mi.position = center
	add_child(mi)


# -------------------------------------------------------------------------
# Obstacles
# -------------------------------------------------------------------------

func _build_obstacles() -> void:
	for obs: HoleGenerator.ObstacleDescriptor in layout.obstacles:
		match obs.type:
			HoleGenerator.ObstacleDescriptor.Type.TREE:
				_build_tree(obs)


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
	trunk.position = Vector3(0.0, -obs.height * 0.30, 0.0)
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

	# Place tree base at terrain height
	var base_y: float = _terrain_height_at(obs.world_position.x, obs.world_position.z)
	body.position = Vector3(
		obs.world_position.x, base_y + obs.height * 0.5, obs.world_position.z
	)
	add_child(body)



# -------------------------------------------------------------------------
# Dynamic hazards
# -------------------------------------------------------------------------

func _build_dynamic_hazards() -> void:
	for desc: HoleGenerator.DynamicHazardDescriptor in layout.dynamic_hazards:
		if not desc.hazard_definition:
			continue
		var script: GDScript = desc.hazard_definition.hazard_script
		if not script:
			continue

		# Apply hazard modifiers before instantiation
		_apply_hazard_modifiers(desc)

		var hazard: Node3D = script.new()
		hazard.setup(desc)

		# Place at terrain height if terrain data is available
		var pos := desc.world_position
		if layout.terrain_data:
			pos.y = layout.terrain_data.get_height_at(pos.x, pos.z)
		hazard.position = pos

		hazard.hazard_activated.connect(_on_hazard_activated)
		add_child(hazard)


func _apply_hazard_modifiers(
	desc: HoleGenerator.DynamicHazardDescriptor,
) -> void:
	if not hazard_modifier_stack:
		return
	var hname: StringName = desc.hazard_definition.hazard_name
	desc.intensity = hazard_modifier_stack.get_effective_value(
		hname, &"intensity", desc.intensity,
	)
	desc.cycle_period = hazard_modifier_stack.get_effective_value(
		hname, &"cycle_period", desc.cycle_period,
	)
	desc.active_duration = hazard_modifier_stack.get_effective_value(
		hname, &"active_duration", desc.active_duration,
	)
	desc.effect_radius = hazard_modifier_stack.get_effective_value(
		hname, &"effect_radius", desc.effect_radius,
	)


func _on_hazard_activated(impulse: Vector3) -> void:
	ball_hit_dynamic_hazard.emit(impulse)


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

## Query terrain height at a world XZ, with fallback for missing terrain data.
func _terrain_height_at(world_x: float, world_z: float) -> float:
	if layout.terrain_data:
		return layout.terrain_data.get_height_at(world_x, world_z)
	return 0.5



func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
