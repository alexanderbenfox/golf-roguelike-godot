## TerrainMeshBuilder — converts TerrainData into renderable geometry + collision.
##
## Pure static functions, no Godot nodes.
##
## Produces:
##   - ArrayMesh via SurfaceTool (two triangles per grid cell, vertex-coloured)
##   - ConcavePolygonShape3D from the same triangles for physics collision
##
## Grid quads overlapping the cup depression are replaced with finely-
## subdivided geometry so the bowl is visible in the mesh (and collision).
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

## Number of sub-divisions per axis when replacing a grid quad around the cup.
const CUP_SUBDIVISIONS: int = 16


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

	# Detect quads to replace with subdivided cup geometry
	var cup_skip: Dictionary = {}  # Vector2i → true
	var has_cup: bool = terrain.cup_depression_depth > 0.0 \
		and terrain.cup_depression_radius > 0.0
	if has_cup:
		cup_skip = _find_cup_quads(terrain)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var collision_faces := PackedVector3Array()
	var quad_count: int = (terrain.grid_width - 1) * (terrain.grid_depth - 1)
	collision_faces.resize(quad_count * 6)  # 2 tris × 3 verts per quad
	var face_idx: int = 0

	for gz: int in range(terrain.grid_depth - 1):
		for gx: int in range(terrain.grid_width - 1):
			if cup_skip.has(Vector2i(gx, gz)):
				continue

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

	# Trim collision array to actual count (some quads were skipped)
	collision_faces.resize(face_idx)

	# Replace skipped quads with subdivided cup depression geometry
	if cup_skip.size() > 0:
		var cup_faces := _build_cup_mesh(st, terrain, biome, cup_skip, uv_scale)
		collision_faces.append_array(cup_faces)

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


# -------------------------------------------------------------------------
# Cup depression mesh
# -------------------------------------------------------------------------

## Find grid quads that overlap the cup depression and need subdivision.
## Any quad with a vertex inside the depression radius is included.
static func _find_cup_quads(terrain: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	var cup_x: float = terrain.cup_position.x
	var cup_z: float = terrain.cup_position.z
	var r: float = terrain.cup_depression_radius
	var r_sq: float = r * r

	for gz: int in range(terrain.grid_depth - 1):
		for gx: int in range(terrain.grid_width - 1):
			# Quad spans between cell-centre vertices
			var qx0: float = terrain.origin.x + (float(gx) + 0.5) * terrain.cell_size
			var qx1: float = terrain.origin.x + (float(gx) + 1.5) * terrain.cell_size
			var qz0: float = terrain.origin.z + (float(gz) + 0.5) * terrain.cell_size
			var qz1: float = terrain.origin.z + (float(gz) + 1.5) * terrain.cell_size
			# Nearest point on the quad rectangle to the cup centre
			var nx: float = clampf(cup_x, qx0, qx1)
			var nz: float = clampf(cup_z, qz0, qz1)
			var ddx: float = nx - cup_x
			var ddz: float = nz - cup_z
			if ddx * ddx + ddz * ddz < r_sq:
				result[Vector2i(gx, gz)] = true
	return result


## Build subdivided geometry for skipped quads around the cup depression.
## Uses terrain.get_height_at() so the analytical bowl is baked into vertices.
## Returns the collision faces for the subdivided triangles.
static func _build_cup_mesh(
	st: SurfaceTool,
	terrain: RefCounted,
	biome: RefCounted,
	cup_quads: Dictionary,
	uv_scale: float,
) -> PackedVector3Array:
	var cup_faces := PackedVector3Array()
	var n: int = CUP_SUBDIVISIONS
	var cup_x: float = terrain.cup_position.x
	var cup_z: float = terrain.cup_position.z
	var cup_r: float = terrain.cup_depression_radius

	for quad_key: Vector2i in cup_quads:
		var gx: int = quad_key.x
		var gz: int = quad_key.y

		# World-space bounds of this quad (vertex positions at cell centres)
		var x0: float = terrain.origin.x + (float(gx) + 0.5) * terrain.cell_size
		var x1: float = terrain.origin.x + (float(gx) + 1.5) * terrain.cell_size
		var z0: float = terrain.origin.z + (float(gz) + 0.5) * terrain.cell_size
		var z1: float = terrain.origin.z + (float(gz) + 1.5) * terrain.cell_size

		# Build (n+1)×(n+1) vertex grid
		var verts: Array[Vector3] = []
		var colors: Array[Color] = []
		var uvs: Array[Vector2] = []
		verts.resize((n + 1) * (n + 1))
		colors.resize((n + 1) * (n + 1))
		uvs.resize((n + 1) * (n + 1))

		for sz: int in range(n + 1):
			for sx: int in range(n + 1):
				var wx: float = lerpf(x0, x1, float(sx) / float(n))
				var wz: float = lerpf(z0, z1, float(sz) / float(n))
				# get_height_at includes the analytical cup depression
				var wy: float = terrain.get_height_at(wx, wz)
				var vi: int = sz * (n + 1) + sx
				verts[vi] = Vector3(wx, wy, wz)
				uvs[vi] = Vector2(wx, wz) * uv_scale

				# Zone color + darken inside the cup depression
				var zone: int = terrain.get_zone_at(wx, wz)
				var c: Color = _zone_color(zone, biome)
				var cdx: float = wx - cup_x
				var cdz: float = wz - cup_z
				var dist: float = sqrt(cdx * cdx + cdz * cdz)
				if dist < cup_r:
					# Match the steep wall shape from TerrainData
					var norm: float = dist / cup_r
					var wall: float = clampf((norm - 0.85) / 0.15, 0.0, 1.0)
					wall = wall * wall * (3.0 - 2.0 * wall)
					# Interior is dark (the "hole"), rim blends back
					c = c.lerp(Color(0.02, 0.02, 0.02), (1.0 - wall) * 0.9)
				colors[vi] = c

		# Emit triangles for each sub-quad
		for sz: int in range(n):
			for sx: int in range(n):
				var i00: int = sz * (n + 1) + sx
				var i10: int = i00 + 1
				var i01: int = i00 + (n + 1)
				var i11: int = i01 + 1

				# Triangle 1
				st.set_color(colors[i00])
				st.set_uv(uvs[i00])
				st.add_vertex(verts[i00])
				st.set_color(colors[i10])
				st.set_uv(uvs[i10])
				st.add_vertex(verts[i10])
				st.set_color(colors[i01])
				st.set_uv(uvs[i01])
				st.add_vertex(verts[i01])

				# Triangle 2
				st.set_color(colors[i10])
				st.set_uv(uvs[i10])
				st.add_vertex(verts[i10])
				st.set_color(colors[i11])
				st.set_uv(uvs[i11])
				st.add_vertex(verts[i11])
				st.set_color(colors[i01])
				st.set_uv(uvs[i01])
				st.add_vertex(verts[i01])

				# Collision faces
				cup_faces.append(verts[i00])
				cup_faces.append(verts[i10])
				cup_faces.append(verts[i01])
				cup_faces.append(verts[i10])
				cup_faces.append(verts[i11])
				cup_faces.append(verts[i01])

	return cup_faces
