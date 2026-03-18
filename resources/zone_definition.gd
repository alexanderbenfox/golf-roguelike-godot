## ZoneDefinition — configurable properties for a single terrain zone type.
##
## Used by BiomeDefinition to define per-zone colors, friction, and terrain
## shaping. Each zone type (fairway, rough, green, etc.) gets one of these
## as an editor-tweakable resource.
class_name ZoneDefinition
extends Resource

## Which zone this definition applies to (matches TerrainData.ZoneType enum).
@export_enum("Fairway", "Rough", "Green", "Tee", "Bunker", "Water", "Lava", "OOB")
var zone_type: int = 0

## Vertex color used when rendering terrain in flat-color mode.
@export var color: Color = Color.WHITE

@export_group("Physics")

## Friction multiplier applied to ball rolling on this zone.
## 1.0 = baseline. Higher = more friction (ball slows faster).
@export_range(0.0, 10.0, 0.05) var friction: float = 1.0

## Bounce multiplier for this zone (multiplied with ball/ground bounce).
@export_range(0.0, 3.0, 0.05) var bounce_modifier: float = 1.0

@export_group("Terrain Shaping")

## Multiplier on terrain height above ground_height (hills).
## 0.0 = no hills, 1.0 = full noise, 2.0 = exaggerated hills.
@export_range(0.0, 5.0, 0.05) var hill_scale: float = 1.0

## Multiplier on terrain depth below ground_height (valleys).
## 0.0 = no valleys, 1.0 = full noise, 2.0 = exaggerated valleys.
@export_range(0.0, 5.0, 0.05) var valley_scale: float = 1.0

## Exponent applied to hill noise values. Controls hill shape:
## < 1.0 = rounded/plateau tops, 1.0 = linear, > 1.0 = peaked/sharp.
@export_range(0.1, 3.0, 0.05) var hill_shape: float = 1.0

## Exponent applied to valley noise values. Controls valley shape:
## < 1.0 = broad/flat bottoms, 1.0 = linear, > 1.0 = narrow/V-shaped.
@export_range(0.1, 3.0, 0.05) var valley_shape: float = 1.0

## Constant vertical offset applied to this zone (metres).
## Negative = depressed (bunkers), positive = raised.
@export_range(-5.0, 5.0, 0.05) var height_offset: float = 0.0

@export_group("Rendering")

## Optional texture for splatmap-based rendering (Phase 6+).
## When set and a terrain ShaderMaterial is in use, this texture is sampled
## for cells painted with this zone type.
@export var texture: Texture2D = null
