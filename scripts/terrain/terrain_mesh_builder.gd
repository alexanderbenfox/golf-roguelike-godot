## TerrainMeshBuilder — converts TerrainData into renderable geometry + collision.
##
## Pure static functions, no Godot nodes.
##
## Produces:
##   - ArrayMesh via SurfaceTool (two triangles per grid cell, vertex-coloured)
##   - ConcavePolygonShape3D from the same triangles for physics collision
##
## Vertex colours come from zone type, giving natural blending at zone boundaries
## because the GPU interpolates vertex colours across shared triangle edges.
class_name TerrainMeshBuilder
extends RefCounted

const TerrainDataScript = preload("res://scripts/terrain/terrain_data.gd")

# ---- Zone colours (meadow defaults — will come from BiomeDefinition in Phase 6) ----

const FAIRWAY_COLOR  := Color(0.20, 0.55, 0.15)
const GREEN_COLOR    := Color(0.15, 0.65, 0.15)
const TEE_COLOR      := Color(0.85, 0.85, 0.85)
const ROUGH_COLOR    := Color(0.30, 0.48, 0.12)
const BUNKER_COLOR   := Color(0.85, 0.78, 0.50)
const WATER_COLOR    := Color(0.15, 0.35, 0.65)
const LAVA_COLOR     := Color(0.85, 0.25, 0.05)
const OOB_COLOR      := Color(0.20, 0.35, 0.10)


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

## Build an ArrayMesh and ConcavePolygonShape3D from a TerrainData instance.
## Returns {"mesh": ArrayMesh, "shape": ConcavePolygonShape3D}.
static func build(terrain: RefCounted) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var collision_faces := PackedVector3Array()
	var quad_count: int = (terrain.grid_width - 1) * (terrain.grid_depth - 1)
	collision_faces.resize(quad_count * 6)  # 2 tris × 3 verts per quad
	var face_idx: int = 0

	for gz: int in range(terrain.grid_depth - 1):
		for gx: int in range(terrain.grid_width - 1):
			# Four corners of this quad
			var v00: Vector3 = terrain.grid_to_world(gx, gz)
			var v10: Vector3 = terrain.grid_to_world(gx + 1, gz)
			var v01: Vector3 = terrain.grid_to_world(gx, gz + 1)
			var v11: Vector3 = terrain.grid_to_world(gx + 1, gz + 1)

			# Vertex colours from zone type
			var c00: Color = _zone_color(terrain.zones[terrain._idx(gx, gz)])
			var c10: Color = _zone_color(terrain.zones[terrain._idx(gx + 1, gz)])
			var c01: Color = _zone_color(terrain.zones[terrain._idx(gx, gz + 1)])
			var c11: Color = _zone_color(terrain.zones[terrain._idx(gx + 1, gz + 1)])

			# Triangle 1: v00 → v10 → v01
			st.set_color(c00)
			st.add_vertex(v00)
			st.set_color(c10)
			st.add_vertex(v10)
			st.set_color(c01)
			st.add_vertex(v01)

			# Triangle 2: v10 → v11 → v01
			st.set_color(c10)
			st.add_vertex(v10)
			st.set_color(c11)
			st.add_vertex(v11)
			st.set_color(c01)
			st.add_vertex(v01)

			# Collision faces (same triangles)
			collision_faces[face_idx] = v00
			collision_faces[face_idx + 1] = v10
			collision_faces[face_idx + 2] = v01
			collision_faces[face_idx + 3] = v10
			collision_faces[face_idx + 4] = v11
			collision_faces[face_idx + 5] = v01
			face_idx += 6

	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision_faces)

	return {"mesh": mesh, "shape": shape}


## Creates a StandardMaterial3D that renders vertex colours as albedo.
static func create_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	return mat


# -------------------------------------------------------------------------
# Internals
# -------------------------------------------------------------------------

static func _zone_color(zone_byte: int) -> Color:
	match zone_byte:
		TerrainDataScript.ZoneType.FAIRWAY:
			return FAIRWAY_COLOR
		TerrainDataScript.ZoneType.GREEN:
			return GREEN_COLOR
		TerrainDataScript.ZoneType.TEE:
			return TEE_COLOR
		TerrainDataScript.ZoneType.BUNKER:
			return BUNKER_COLOR
		TerrainDataScript.ZoneType.WATER:
			return WATER_COLOR
		TerrainDataScript.ZoneType.LAVA:
			return LAVA_COLOR
		TerrainDataScript.ZoneType.OOB:
			return OOB_COLOR
		_:  # ROUGH or unknown
			return ROUGH_COLOR
