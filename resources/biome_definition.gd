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

## Width variation along the fairway. 0.0 = uniform width,
## 1.0 = dramatic ±50% width pulses (wider landing zones, narrow chokes).
@export_range(0.0, 1.0, 0.05) var fairway_width_variation: float = 0.0

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

@export_group("Terrain Archetype")

enum TerrainArchetype {
	CONTINENTAL = 0,        ## Default: noise-based terrain with carved fairway
	ISLAND = 1,             ## Base below water, raised island blobs + bridges
	VALLEY_CORRIDOR = 2,    ## High base, carved winding valley between ridges
	DONUT_LAKE = 3,         ## Ring-shaped course around a central pond
	ASCENDING_PLATEAU = 4,  ## Stacked elevation tiers, hole near the top
}

## Controls the fundamental terrain shape for this biome.
@export var terrain_archetype: TerrainArchetype = TerrainArchetype.CONTINENTAL

## When true, the fairway has gaps (water/rough breaks) the player must
## hit across. Works with any archetype.
@export var discontinuous_fairway: bool = false

@export_subgroup("Island")

## Number of island blobs (auto-scaled slightly by par).
@export_range(2, 6) var island_count: int = 3

## Minimum island radius (metres).
@export_range(10.0, 40.0, 0.5) var island_radius_min: float = 15.0

## Maximum island radius (metres).
@export_range(20.0, 60.0, 0.5) var island_radius_max: float = 35.0

## Organic edge variation — noise-perturbed island boundaries (0 = circle).
@export_range(0.0, 1.0, 0.05) var island_noise_distortion: float = 0.3

## Bridge width as fraction of fairway width (connects islands).
@export_range(0.5, 1.0, 0.05) var bridge_width_factor: float = 0.7

@export_subgroup("Valley Corridor")

## Corridor width as multiple of fairway_width.
@export_range(1.0, 3.0, 0.1) var corridor_width_multiplier: float = 1.5

## Wall steepness (0 = gentle slopes, 1 = near-vertical cliffs).
@export_range(0.0, 1.0, 0.05) var wall_steepness: float = 0.7

## Chance of side pockets along corridor for bunkers/shortcuts.
@export_range(0.0, 1.0, 0.1) var alcove_density: float = 0.3

## Height of surrounding ridges above the valley floor (metres).
@export_range(5.0, 20.0, 0.5) var ridge_height: float = 12.0

@export_subgroup("Donut Lake")

## Minimum radius of the central lake (metres).
@export_range(15.0, 60.0, 1.0) var lake_radius_min: float = 25.0

## Maximum radius of the central lake (metres).
@export_range(20.0, 80.0, 1.0) var lake_radius_max: float = 40.0

## Depth below water_height for the lake bed (metres).
@export_range(0.5, 5.0, 0.1) var lake_depth: float = 2.0

@export_subgroup("Ascending Plateau")

## Number of discrete elevation tiers from tee to cup.
@export_range(2, 6) var step_count: int = 3

## Height gain per tier (metres).
@export_range(2.0, 10.0, 0.5) var step_height: float = 4.0

## Random ± variation applied to each tier's height (metres).
## 0 = uniform steps, higher = irregular staircase.
@export_range(0.0, 5.0, 0.5) var step_height_variation: float = 1.5

## Steepness of transitions between tiers (0 = gentle ramp, 1 = cliff).
@export_range(0.0, 1.0, 0.05) var step_steepness: float = 0.7

## Platform radius multiplier — controls how wide each step/platform is
## relative to the fairway width (1.0 = compact, 3.0 = sprawling).
@export_range(0.8, 4.0, 0.1) var step_platform_scale: float = 1.8

@export_group("Curve Routing")

## Per-biome curve overrides. -1 = use HoleGenConfig default.

## Minimum bends per hole for this biome (-1 = use config).
@export_range(-1, 8) var curve_min_bends: int = -1

## Maximum bends per hole for this biome (-1 = use config).
@export_range(-1, 8) var curve_max_bends: int = -1

## Turn angle intensity (-1.0 = use config).
## 0.0 = gentle 5–20°, 0.5 = default 30–75°, 1.0 = tight 60–120°.
@export_range(-1.0, 1.0, 0.05) var curve_tightness: float = -1.0

## S-curve bias (-1.0 = use config).
## 0.0 = random bend directions, 1.0 = always alternate left/right.
@export_range(-1.0, 1.0, 0.05) var curve_s_bias: float = -1.0

## Smoothing subdivisions per bend (-1 = use config).
## 0 = sharp doglegs, higher = smoother arcs.
@export_range(-1, 8) var curve_smoothing: int = -1

## Horizontal spread amplification (-1.0 = use config).
## 0.0 = no amplification. 1.0 = dramatic sideways extent.
@export_range(-1.0, 1.0, 0.05) var curve_spread: float = -1.0

@export_group("Inter-Curve Features")

## Density of environmental features between S-curve legs.
## 0.0 = empty rough, 1.0 = packed with hills, ponds, and trees.
@export_range(0.0, 1.0, 0.05) var inter_curve_density: float = 0.0

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
	# Curves: sweeping S-bends with real horizontal spread
	biome.curve_min_bends = 2
	biome.curve_max_bends = 3
	biome.curve_tightness = 0.55
	biome.curve_s_bias = 0.85
	biome.curve_smoothing = 4
	biome.curve_spread = 0.5
	# Width variation: gentle organic pulses
	biome.fairway_width_variation = 0.35
	# Between curves: ponds, hills, and scattered trees
	biome.inter_curve_density = 0.5
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
	# Curves: tight winding turns through the canyon
	biome.curve_min_bends = 2
	biome.curve_max_bends = 4
	biome.curve_tightness = 0.75
	biome.curve_s_bias = 0.7
	biome.curve_smoothing = 3
	biome.curve_spread = 0.6
	# Width variation: dramatic narrows through canyon walls
	biome.fairway_width_variation = 0.5
	# Between curves: rocky outcrops and elevation changes
	biome.inter_curve_density = 0.7
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
	# Curves: sweeping bends across open dunes
	biome.curve_min_bends = 1
	biome.curve_max_bends = 3
	biome.curve_tightness = 0.45
	biome.curve_s_bias = 0.6
	biome.curve_smoothing = 5
	biome.curve_spread = 0.4
	# Width variation: broad open sections, narrow dune passes
	biome.fairway_width_variation = 0.4
	# Between curves: dune ridges and sparse features
	biome.inter_curve_density = 0.35
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


# ---- Archetype variant factories --------------------------------------------

static func create_island_meadow() -> BiomeDefinition:
	var biome := create_meadow()
	biome.biome_name = "Island Meadow"
	biome.terrain_archetype = TerrainArchetype.ISLAND
	biome.water_height = 0.0
	biome.island_count = 4
	biome.island_radius_min = 18.0
	biome.island_radius_max = 40.0
	biome.bridge_width_factor = 0.7
	# Curves: S-bends hopping between islands
	biome.curve_min_bends = 2
	biome.curve_max_bends = 3
	biome.curve_tightness = 0.55
	biome.curve_s_bias = 0.85
	biome.curve_smoothing = 4
	biome.curve_spread = 0.45
	biome.inter_curve_density = 0.4
	return biome


static func create_valley_canyon() -> BiomeDefinition:
	var biome := create_canyon()
	biome.biome_name = "Valley Canyon"
	biome.terrain_archetype = TerrainArchetype.VALLEY_CORRIDOR
	biome.corridor_width_multiplier = 1.5
	biome.wall_steepness = 0.75
	biome.ridge_height = 12.0
	# Curves: tight serpentine winding through the valley
	biome.curve_min_bends = 3
	biome.curve_max_bends = 5
	biome.curve_tightness = 0.8
	biome.curve_s_bias = 0.95
	biome.curve_smoothing = 3
	biome.curve_spread = 0.8
	# Width: dramatic narrows and wide spots in the valley
	biome.fairway_width_variation = 0.55
	# Between curves: tall ridges blocking line-of-sight
	biome.inter_curve_density = 0.9
	return biome


static func create_donut_meadow() -> BiomeDefinition:
	var biome := create_meadow()
	biome.biome_name = "Donut Meadow"
	biome.terrain_archetype = TerrainArchetype.DONUT_LAKE
	biome.water_height = 0.0
	biome.lake_radius_min = 25.0
	biome.lake_radius_max = 40.0
	biome.lake_depth = 2.0
	biome.curve_spread = 0.45
	biome.inter_curve_density = 0.4
	return biome


static func create_ascending_canyon() -> BiomeDefinition:
	var biome := create_canyon()
	biome.biome_name = "Ascending Canyon"
	biome.terrain_archetype = TerrainArchetype.ASCENDING_PLATEAU
	biome.step_count = 4
	biome.step_height = 5.0
	biome.step_height_variation = 1.5
	biome.step_steepness = 0.7
	biome.step_platform_scale = 1.8
	# Curves: winding bends between platforms
	biome.curve_min_bends = 2
	biome.curve_max_bends = 3
	biome.curve_tightness = 0.6
	biome.curve_s_bias = 0.7
	biome.curve_smoothing = 3
	biome.curve_spread = 0.5
	# Width: wide platforms, narrow connecting paths
	biome.fairway_width_variation = 0.45
	# Between curves: elevated terrain between platforms
	biome.inter_curve_density = 0.6
	return biome


static func create_island_desert() -> BiomeDefinition:
	var biome := create_desert()
	biome.biome_name = "Oasis Desert"
	biome.terrain_archetype = TerrainArchetype.ISLAND
	biome.water_height = -0.5
	biome.island_count = 3
	biome.island_radius_min = 20.0
	biome.island_radius_max = 45.0
	biome.bridge_width_factor = 0.6
	# Curves: sweeps between oasis islands
	biome.curve_min_bends = 1
	biome.curve_max_bends = 3
	biome.curve_tightness = 0.45
	biome.curve_s_bias = 0.6
	biome.curve_smoothing = 5
	biome.curve_spread = 0.35
	biome.inter_curve_density = 0.3
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
