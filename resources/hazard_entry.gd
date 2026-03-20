## HazardEntry — pairs a HazardDefinition with a per-biome density multiplier.
##
## BiomeDefinition holds an Array[HazardEntry] so each biome can reference
## the same HazardDefinition at different densities, or mix multiple hazard
## types on a single biome.
class_name HazardEntry
extends Resource

## The hazard type to place.
@export var definition: HazardDefinition

## Density multiplier for this hazard within this biome.
## 0.0 = disabled, 1.0 = normal, 2.0 = double density.
@export_range(0.0, 3.0, 0.1) var density: float = 1.0
