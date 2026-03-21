## BiomeDefinition — describes all visual and mechanical properties for a biome.
##
## Each biome (Meadow, Canyon, Desert, etc.) is a .tres resource with per-zone
## colors, friction, terrain noise parameters, and optional material overrides.
## Designers edit these in the Inspector to tune how each biome looks and plays.
@tool
class_name BiomeDefinition
extends Resource

const TerrainDataScript = preload("res://scripts/terrain/terrain_data.gd")

## Display name for UI.
@export var biome_name: String = "Meadow"

## Per-zone definitions. One entry per zone type used in TerrainData.ZoneType.
## Each ZoneDefinition holds the zone's color, friction, bounce, terrain
## shaping, and future texture. Auto-populated with all 8 zone types on creation.
@export var zones: Array[ZoneDefinition]

@export_group("Terrain Noise")

## Base noise amplitude — controls overall hill/valley height (metres).
@export_range(0.0, 20.0, 0.1) var terrain_amplitude: float = 3.0

## Base noise frequency — controls feature density.
## Lower = broad rolling hills, higher = tightly packed features.
@export_range(0.001, 0.1, 0.001) var terrain_frequency: float = 0.012

## Number of noise octaves (detail layers).
@export_range(1, 8) var noise_octaves: int = 3

## Frequency multiplier between successive octaves.
@export_range(1.0, 4.0, 0.1) var noise_lacunarity: float = 2.0

## Amplitude multiplier between successive octaves (persistence).
@export_range(0.0, 1.0, 0.05) var noise_gain: float = 0.5

@export_group("Elevation")

## Minimum terrain height (metres). Heights are clamped to this after
## all generation passes.
@export_range(-20.0, 0.0, 0.1) var min_height: float = -2.0

## Maximum terrain height (metres). Heights are clamped to this after
## all generation passes.
@export_range(0.0, 30.0, 0.1) var max_height: float = 8.0

@export_group("Plateaus")

## How aggressively heights snap to discrete terrace levels (0 = smooth
## natural noise, 1 = hard flat mesas with steep cliff transitions).
@export_range(0.0, 1.0, 0.05) var plateau_factor: float = 0.0

## Number of discrete elevation bands. More levels = thinner terraces.
## Only used when plateau_factor > 0.
@export_range(2, 8) var plateau_levels: int = 3

@export_group("Fairway Shaping")

## How aggressively the fairway corridor blends toward the spine elevation.
## 0.0 = no carving (terrain unchanged), 1.0 = perfectly flat fairway.
@export_range(0.0, 1.0, 0.05) var fairway_flatten_strength: float = 0.85

## Radius of the flattened area around the green (metres).
@export_range(3.0, 20.0, 0.5) var green_flatten_radius: float = 10.0

## Radius of the flattened area around the tee (metres).
@export_range(2.0, 10.0, 0.5) var tee_flatten_radius: float = 5.0

@export_group("Hazards")

## Height below which terrain becomes water. Set to -999 to disable.
@export_range(-20.0, 10.0, 0.1) var water_height: float = -999.0

## Height below which terrain becomes lava. Set to -999 to disable.
@export_range(-20.0, 10.0, 0.1) var lava_height: float = -999.0

## Data-driven hazard types for this biome. Each entry pairs a HazardDefinition
## with a density multiplier (replaces the old dynamic_hazard_density float).
@export var hazard_definitions: Array[Resource] = []  # Array[HazardEntry]

@export_group("Wind")

## Average wind speed (m/s). 0 = no wind for this biome.
@export_range(0.0, 15.0, 0.1) var base_wind_strength: float = 0.0

## Random ± range around base strength per hole.
@export_range(0.0, 10.0, 0.1) var wind_variance: float = 0.0

@export_group("Rendering")

## If set, replaces the default vertex-color material on the terrain mesh.
## Use a ShaderMaterial with a splatmap approach for textured terrain.
## The mesh always includes UV coordinates (world XZ * uv_scale).
@export var material_override: Material = null

## UV tiling scale for terrain mesh (world_position * uv_scale = UV).
## Controls texture repeat density when material_override is set.
@export_range(0.01, 1.0, 0.01) var uv_scale: float = 0.1

@export_group("Slope Coloring")

## Color applied to steep terrain faces (cliff sides, hill faces).
## Blended over the zone color based on surface steepness.
@export var slope_color: Color = Color(0.45, 0.35, 0.25)

## Steepness below which no slope coloring is applied (0 = flat, 1 = vertical).
## Surfaces steeper than this threshold start blending toward slope_color.
@export_range(0.0, 1.0, 0.05) var slope_threshold: float = 0.4

## Maximum blend strength toward slope_color at fully vertical surfaces.
## 0 = no slope coloring, 1 = fully replaces zone color on vertical faces.
@export_range(0.0, 1.0, 0.05) var slope_color_strength: float = 0.8


# ---- Auto-populate zones on creation ----------------------------------------

func _init() -> void:
	if zones.size() > 0:
		return
	# ZoneType enum: FAIRWAY=0, ROUGH=1, GREEN=2, TEE=3,
	# BUNKER=4, WATER=5, LAVA=6, OOB=7
	_add_zone(0, Color(0.20, 0.55, 0.15), 1.0)  # FAIRWAY
	_add_zone(1, Color(0.30, 0.48, 0.12), 1.5)  # ROUGH
	_add_zone(2, Color(0.15, 0.65, 0.15), 0.7)  # GREEN
	_add_zone(3, Color(0.85, 0.85, 0.85), 1.0)  # TEE
	_add_zone(4, Color(0.85, 0.78, 0.50), 3.0)  # BUNKER
	_add_zone(5, Color(0.15, 0.35, 0.65), 1.5)  # WATER
	_add_zone(6, Color(0.85, 0.25, 0.05), 1.5)  # LAVA
	_add_zone(7, Color(0.20, 0.35, 0.10), 1.5)  # OOB


func _add_zone(type: int, color: Color, friction: float) -> void:
	var z := ZoneDefinition.new()
	z.zone_type = type
	z.color = color
	z.friction = friction
	zones.append(z)


# ---- Lookup helpers (linear scan of ≤8 entries — negligible cost) ----------

func get_zone_def(zone_type: int) -> ZoneDefinition:
	for z in zones:
		if z.zone_type == zone_type:
			return z
	return null


func get_friction(zone_type: int) -> float:
	var z := get_zone_def(zone_type)
	return z.friction if z else 1.0


func get_color(zone_type: int) -> Color:
	var z := get_zone_def(zone_type)
	return z.color if z else Color.MAGENTA


func get_bounce_modifier(zone_type: int) -> float:
	var z := get_zone_def(zone_type)
	return z.bounce_modifier if z else 1.0


# ---- Default biome factories ------------------------------------------------

static func create_meadow() -> BiomeDefinition:
	var biome := BiomeDefinition.new()
	biome.biome_name = "Meadow"
	biome.water_height = 0.0
	biome.base_wind_strength = 1.0
	biome.wind_variance = 1.5
	# Plateaus: gentle terracing, still mostly smooth
	biome.plateau_factor = 0.3
	biome.plateau_levels = 3
	# Slope coloring: exposed earth/dirt on hillsides
	biome.slope_color = Color(0.45, 0.35, 0.25)
	biome.slope_threshold = 0.3
	biome.slope_color_strength = 0.8
	# Noise defaults are already meadow-appropriate
	biome.zones = [
		_zone(
			TerrainDataScript.ZoneType.FAIRWAY,
			Color(0.20, 0.55, 0.15), 1.0,
			0.3, 0.2, 0.8, 1.0,
		),
		_zone(
			TerrainDataScript.ZoneType.ROUGH,
			Color(0.30, 0.48, 0.12), 1.5,
			1.0, 1.0, 1.0, 1.0,
		),
		_zone(
			TerrainDataScript.ZoneType.GREEN,
			Color(0.15, 0.65, 0.15), 0.7,
			0.1, 0.1, 0.8, 0.8,
		),
		_zone(
			TerrainDataScript.ZoneType.TEE,
			Color(0.85, 0.85, 0.85), 1.0,
			0.1, 0.1, 0.8, 0.8,
		),
		_zone_ex(
			TerrainDataScript.ZoneType.BUNKER,
			Color(0.85, 0.78, 0.50), 3.0,
			0.2, 0.5, 0.8, 0.6, -1.5,
		),
		_zone(
			TerrainDataScript.ZoneType.WATER,
			Color(0.15, 0.35, 0.65), 1.5,
			0.5, 1.5, 1.0, 0.5,
		),
		_zone(
			TerrainDataScript.ZoneType.LAVA,
			Color(0.85, 0.25, 0.05), 1.5,
			0.5, 1.5, 1.0, 0.5,
		),
		_zone(
			TerrainDataScript.ZoneType.OOB,
			Color(0.20, 0.35, 0.10), 1.5,
			1.2, 1.0, 1.0, 1.0,
		),
	]
	return biome


static func create_canyon() -> BiomeDefinition:
	var biome := BiomeDefinition.new()
	biome.biome_name = "Canyon"
	biome.water_height = -0.5
	biome.base_wind_strength = 2.5
	biome.wind_variance = 2.0
	# Plateaus: prominent mesas with steep cliffs
	biome.plateau_factor = 0.6
	biome.plateau_levels = 4
	# Slope coloring: red-brown sandstone cliff faces
	biome.slope_color = Color(0.55, 0.30, 0.20)
	biome.slope_threshold = 0.25
	biome.slope_color_strength = 0.85
	biome.terrain_amplitude = 8.0
	biome.terrain_frequency = 0.018
	biome.noise_octaves = 4
	biome.noise_lacunarity = 2.2
	biome.noise_gain = 0.55
	biome.min_height = -4.0
	biome.max_height = 14.0
	biome.fairway_flatten_strength = 0.7
	biome.green_flatten_radius = 12.0
	biome.tee_flatten_radius = 6.0
	biome.zones = [
		_zone(
			TerrainDataScript.ZoneType.FAIRWAY,
			Color(0.55, 0.42, 0.28), 1.1,
			0.4, 0.3, 0.9, 1.0,
		),
		_zone(
			TerrainDataScript.ZoneType.ROUGH,
			Color(0.50, 0.38, 0.22), 1.8,
			1.5, 1.3, 1.2, 1.1,
		),
		_zone(
			TerrainDataScript.ZoneType.GREEN,
			Color(0.45, 0.52, 0.30), 0.8,
			0.1, 0.1, 0.8, 0.8,
		),
		_zone(
			TerrainDataScript.ZoneType.TEE,
			Color(0.70, 0.65, 0.55), 1.0,
			0.1, 0.1, 0.8, 0.8,
		),
		_zone_ex(
			TerrainDataScript.ZoneType.BUNKER,
			Color(0.75, 0.60, 0.35), 3.5,
			0.3, 0.8, 0.7, 0.5, -1.5,
		),
		_zone_ex(
			TerrainDataScript.ZoneType.WATER,
			Color(0.12, 0.28, 0.50), 1.5,
			0.3, 2.0, 1.0, 0.4, -1.0,
		),
		_zone(
			TerrainDataScript.ZoneType.LAVA,
			Color(0.85, 0.25, 0.05), 1.5,
			0.5, 1.5, 1.0, 0.5,
		),
		_zone(
			TerrainDataScript.ZoneType.OOB,
			Color(0.45, 0.35, 0.20), 2.0,
			1.8, 1.5, 1.3, 1.2,
		),
	]
	return biome


static func create_desert() -> BiomeDefinition:
	var biome := BiomeDefinition.new()
	biome.biome_name = "Desert"
	biome.base_wind_strength = 4.0
	biome.wind_variance = 3.0
	# Plateaus: moderate dune plateaus
	biome.plateau_factor = 0.4
	biome.plateau_levels = 3
	# Slope coloring: dark compacted sand/hardpan on dune faces
	biome.slope_color = Color(0.50, 0.40, 0.28)
	biome.slope_threshold = 0.35
	biome.slope_color_strength = 0.75
	biome.terrain_amplitude = 4.5
	biome.terrain_frequency = 0.008
	biome.noise_octaves = 3
	biome.noise_lacunarity = 2.5
	biome.noise_gain = 0.4
	biome.min_height = -1.0
	biome.max_height = 10.0
	biome.fairway_flatten_strength = 0.9
	biome.green_flatten_radius = 8.0
	biome.tee_flatten_radius = 5.0
	biome.zones = [
		_zone(
			TerrainDataScript.ZoneType.FAIRWAY,
			Color(0.82, 0.72, 0.45), 1.2,
			0.5, 0.3, 1.2, 0.8,
		),
		_zone(
			TerrainDataScript.ZoneType.ROUGH,
			Color(0.78, 0.65, 0.38), 2.0,
			1.2, 0.8, 1.3, 1.0,
		),
		_zone(
			TerrainDataScript.ZoneType.GREEN,
			Color(0.40, 0.55, 0.25), 0.7,
			0.1, 0.1, 0.8, 0.8,
		),
		_zone(
			TerrainDataScript.ZoneType.TEE,
			Color(0.85, 0.80, 0.65), 1.0,
			0.1, 0.1, 0.8, 0.8,
		),
		_zone_ex(
			TerrainDataScript.ZoneType.BUNKER,
			Color(0.90, 0.82, 0.55), 4.0,
			0.4, 0.6, 0.9, 0.5, -1.5,
		),
		_zone(
			TerrainDataScript.ZoneType.WATER,
			Color(0.10, 0.30, 0.55), 1.5,
			0.3, 1.8, 1.0, 0.4,
		),
		_zone(
			TerrainDataScript.ZoneType.LAVA,
			Color(0.90, 0.30, 0.05), 1.5,
			0.6, 1.5, 1.0, 0.5,
		),
		_zone(
			TerrainDataScript.ZoneType.OOB,
			Color(0.70, 0.58, 0.35), 2.5,
			1.5, 1.0, 1.2, 1.0,
		),
	]
	return biome


static func _zone(
	type: int, color: Color, friction: float,
	hill_scale: float = 1.0, valley_scale: float = 1.0,
	hill_shape: float = 1.0, valley_shape: float = 1.0,
) -> ZoneDefinition:
	var z := ZoneDefinition.new()
	z.zone_type = type
	z.color = color
	z.friction = friction
	z.hill_scale = hill_scale
	z.valley_scale = valley_scale
	z.hill_shape = hill_shape
	z.valley_shape = valley_shape
	return z


static func _zone_ex(
	type: int, color: Color, friction: float,
	hill_scale: float, valley_scale: float,
	hill_shape: float, valley_shape: float,
	height_offset: float,
) -> ZoneDefinition:
	var z := _zone(
		type, color, friction,
		hill_scale, valley_scale, hill_shape, valley_shape,
	)
	z.height_offset = height_offset
	return z
