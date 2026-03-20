## TerrainMeshBuilder — converts TerrainData into renderable geometry + collision.
##
## Pure static functions, no Godot nodes.
##
## Produces:
##   - ArrayMesh via SurfaceTool (two triangles per grid cell, vertex-coloured)
##   - ConcavePolygonShape3D from the same triangles for physics collision
##
## Vertex colours come from the BiomeDefinition on TerrainData, giving natural
## blending at zone boundaries because the GPU interpolates vertex colours
## across shared triangle edges.
##
## UV coordinates are always generated (world XZ * uv_scale) so that a
## material_override with textures works when plugged in.
class_name TerrainMeshBuilder
extends RefCounted

const TerrainDataScript = preload("res://scripts/terrain/terrain_data.gd")
const BiomeDefinitionScript = preload("res://resources/biome_definition.gd")

# Fallback colors when no biome is set (meadow defaults)
const _FALLBACK_COLORS: Dictionary = {
	0: Color(0.20, 0.55, 0.15),  # FAIRWAY
	1: Color(0.30, 0.48, 0.12),  # ROUGH
	2: Color(0.15, 0.65, 0.15),  # GREEN
	3: Color(0.85, 0.85, 0.85),  # TEE
	4: Color(0.85, 0.78, 0.50),  # BUNKER
	5: Color(0.15, 0.35, 0.65),  # WATER
	6: Color(0.85, 0.25, 0.05),  # LAVA
	7: Color(0.20, 0.35, 0.10),  # OOB
}


# -------------------------------------------------------------------------
# Public API
# -------------------------------------------------------------------------

## Build an ArrayMesh and ConcavePolygonShape3D from a TerrainData instance.
## Returns {"mesh": ArrayMesh, "shape": ConcavePolygonShape3D}.
static func build(terrain: RefCounted) -> Dictionary:
	var biome: RefCounted = terrain.biome  # BiomeDefinition or null
	var uv_scale: float = biome.uv_scale if biome else 0.1

	# Slope coloring parameters
	var slope_color: Color = biome.slope_color if biome else Color(0.45, 0.35, 0.25)
	var slope_threshold: float = biome.slope_threshold if biome else 0.4
	var slope_strength: float = biome.slope_color_strength if biome else 0.0
	var slope_range: float = 1.0 - slope_threshold  # denominator for blend factor

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

			# Vertex colours from zone type (via biome or fallback)
			var c00: Color = _zone_color(terrain.zones[terrain.idx(gx, gz)], biome)
			var c10: Color = _zone_color(terrain.zones[terrain.idx(gx + 1, gz)], biome)
			var c01: Color = _zone_color(terrain.zones[terrain.idx(gx, gz + 1)], biome)
			var c11: Color = _zone_color(terrain.zones[terrain.idx(gx + 1, gz + 1)], biome)

			# Slope-dependent coloring: blend toward slope_color on steep faces
			if slope_strength > 0.0 and slope_range > 0.0:
				c00 = _apply_slope_color(c00, terrain, v00, slope_color, slope_threshold, slope_range, slope_strength)
				c10 = _apply_slope_color(c10, terrain, v10, slope_color, slope_threshold, slope_range, slope_strength)
				c01 = _apply_slope_color(c01, terrain, v01, slope_color, slope_threshold, slope_range, slope_strength)
				c11 = _apply_slope_color(c11, terrain, v11, slope_color, slope_threshold, slope_range, slope_strength)

			# UV coordinates from world XZ position
			var uv00 := Vector2(v00.x, v00.z) * uv_scale
			var uv10 := Vector2(v10.x, v10.z) * uv_scale
			var uv01 := Vector2(v01.x, v01.z) * uv_scale
			var uv11 := Vector2(v11.x, v11.z) * uv_scale

			# Triangle 1: v00 → v10 → v01
			st.set_color(c00)
			st.set_uv(uv00)
			st.add_vertex(v00)
			st.set_color(c10)
			st.set_uv(uv10)
			st.add_vertex(v10)
			st.set_color(c01)
			st.set_uv(uv01)
			st.add_vertex(v01)

			# Triangle 2: v10 → v11 → v01
			st.set_color(c10)
			st.set_uv(uv10)
			st.add_vertex(v10)
			st.set_color(c11)
			st.set_uv(uv11)
			st.add_vertex(v11)
			st.set_color(c01)
			st.set_uv(uv01)
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


## Creates the default vertex-color material, or returns the biome's
## material_override if one is set.
static func create_material(biome: RefCounted = null) -> Material:
	if biome and biome.material_override:
		return biome.material_override
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	return mat


# -------------------------------------------------------------------------
# Internals
# -------------------------------------------------------------------------

static func _zone_color(zone_byte: int, biome: RefCounted) -> Color:
	if biome:
		return biome.get_color(zone_byte)
	return _FALLBACK_COLORS.get(zone_byte, Color(0.30, 0.48, 0.12))


static func _apply_slope_color(
	base_color: Color, terrain: RefCounted, vertex: Vector3,
	slope_color: Color, threshold: float, slope_range: float, strength: float,
) -> Color:
	var normal: Vector3 = terrain.get_normal_at(vertex.x, vertex.z)
	var steepness: float = 1.0 - normal.y  # 0 = flat, 1 = vertical
	if steepness <= threshold:
		return base_color
	var blend := clampf((steepness - threshold) / slope_range, 0.0, 1.0) * strength
	return base_color.lerp(slope_color, blend)
