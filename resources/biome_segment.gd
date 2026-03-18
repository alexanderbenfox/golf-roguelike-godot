## BiomeSegment — one entry in a course's biome sequence.
##
## Pairs a BiomeDefinition with a hole count and terrain size controls.
## CourseManager holds an ordered array of these to define which biome is
## played for each stretch of holes.
##
## Example sequence (9-hole course):
##   [Meadow × 3, Canyon × 3, Desert × 3]
##   → Holes 1-3 = Meadow, 4-6 = Canyon, 7-9 = Desert
class_name BiomeSegment
extends Resource

## The biome used for this stretch of holes.
## Leave null to use the default Meadow biome.
@export var biome: BiomeDefinition = null

## Number of holes to generate with this biome.
@export_range(1, 18) var hole_count: int = 3

@export_group("Terrain Size")

## Grid cell size in metres. Smaller = higher resolution terrain but
## more triangles. 2.0 is the default (~7.5K tris per hole).
@export_range(0.5, 8.0, 0.5) var cell_size: float = 2.0

## Extra margin around the hole bounds (metres). Larger = more visible
## terrain beyond the playable area.
@export_range(10.0, 100.0, 5.0) var margin: float = 30.0
