class_name CourseManager
extends Node

const HoleGeneratorScript = preload("res://scripts/hole_generator.gd")
const HoleGenConfigScript = preload("res://scripts/hole_gen_config.gd")
const BiomeDefinitionScript = preload("res://resources/biome_definition.gd")

signal hole_started(hole_number: int, par: int)
signal course_completed(totals_strokes: int, total_par: int)

## Ordered biome sequence for the course. Each entry specifies a biome and
## how many holes to play on it. Total holes = sum of all hole_counts.
## Example: [Meadow×3, Canyon×3, Desert×3] = 9-hole course.
## When empty, falls back to holes_in_course with the default Meadow biome.
@export var biome_sequence: Array[BiomeSegment] = []

## Total holes in the course (derived from biome_sequence after generation).
var holes_in_course: int = 9

## Procedural generation parameters (par ranges, fairway width, obstacle
## density, etc.). Assign a HoleGenConfig resource here, or leave null
## to use defaults. Biome is resolved from biome_sequence first, then
## config.biome, then Meadow default.
@export var config: Resource = null

var current_hole_index: int = 0
var hole_pars: Array[int] = []
var hole_layouts: Array = []   # Array of HoleGenerator.HoleLayout
var course_seed: int = 0

var scoring_manager: ScoringManager

func _ready() -> void:
	generate_course()


func generate_course(rng_seed: int = 0) -> void:
	course_seed = rng_seed
	var cfg: HoleGenConfig = \
		config as HoleGenConfig if config != null \
		else HoleGenConfigScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	hole_pars.clear()
	hole_layouts.clear()

	# Build ordered list of (biome, hole_count) pairs
	var sequence: Array[Dictionary] = _resolve_sequence()
	var hole_num: int = 0

	for entry: Dictionary in sequence:
		var biome: BiomeDefinition = entry["biome"]
		var count: int = entry["count"]
		var seg_cell_size: float = entry["cell_size"]
		var seg_margin: float = entry["margin"]
		for _hole_idx: int in range(count):
			hole_num += 1
			var par: int = rng.randi_range(
				cfg.min_par, cfg.max_par,
			)
			hole_pars.append(par)
			hole_layouts.append(
				HoleGeneratorScript.generate(
					rng, hole_num, par, cfg, biome,
					seg_cell_size, seg_margin,
				)
			)

	# Update holes_in_course to match actual generated count
	holes_in_course = hole_layouts.size()


## Resolve the biome sequence into an array of {biome, count} dicts.
## When biome_sequence is set in the Inspector, uses that directly.
## When empty, builds a run-based progression sequence from meta_level.
func _resolve_sequence() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if biome_sequence.size() > 0:
		for segment: BiomeSegment in biome_sequence:
			var biome: BiomeDefinition = segment.biome \
				if segment.biome \
				else BiomeDefinitionScript.create_meadow()
			result.append({
				"biome": biome,
				"count": segment.hole_count,
				"cell_size": segment.cell_size,
				"margin": segment.margin,
			})
	else:
		result = _build_run_sequence()
	return result


## Build a biome sequence dynamically based on MetaProgression.meta_level.
## Each meta level introduces one new biome, shifting holes toward harder biomes.
##
## Level 0 (0 runs):   9 Meadow
## Level 1 (2+ runs):  5 Meadow, 4 Canyon
## Level 2 (5+ runs):  3 Meadow, 3 Canyon, 3 Desert
## Level 3 (10+ runs): 2 Meadow, 3 Canyon, 4 Desert
func _build_run_sequence() -> Array[Dictionary]:
	# TODO: Re-enable when meta progression is ready for testing
	# var level: int = MetaProgression.meta_level if MetaProgression else 0
	var level: int = 3

	var meadow: BiomeDefinition = BiomeDefinitionScript.create_meadow()
	var canyon: BiomeDefinition = BiomeDefinitionScript.create_canyon()
	var desert: BiomeDefinition = BiomeDefinitionScript.create_desert()

	var result: Array[Dictionary] = []
	match level:
		0:
			result.append(_seg(meadow, 9))
		1:
			result.append(_seg(meadow, 5))
			result.append(_seg(canyon, 4, 2.5, 35.0))
		2:
			result.append(_seg(meadow, 3))
			result.append(_seg(canyon, 3, 2.5, 35.0))
			result.append(_seg(desert, 3, 2.0, 35.0))
		_:
			# Level 3+: skew toward harder biomes
			result.append(_seg(meadow, 2))
			result.append(_seg(canyon, 3, 2.5, 35.0))
			result.append(_seg(desert, 4, 2.0, 35.0))

	return result


static func _seg(
	biome: BiomeDefinition, count: int,
	cell_size: float = 2.0, margin: float = 30.0,
) -> Dictionary:
	return {
		"biome": biome,
		"count": count,
		"cell_size": cell_size,
		"margin": margin,
	}


func get_current_layout() -> HoleGenerator.HoleLayout:
	if current_hole_index < hole_layouts.size():
		return hole_layouts[current_hole_index]
	return null


func setup(manager: ScoringManager) -> void:
	scoring_manager = manager
	scoring_manager.hole_completed.connect(_on_hole_completed)


func start_course() -> void:
	current_hole_index = 0
	start_next_hole()


func start_next_hole() -> void:
	if current_hole_index >= hole_layouts.size():
		complete_course()
		return

	var par: int = hole_pars[current_hole_index]
	var hole_num: int = current_hole_index + 1

	print("Starting hole ", hole_num, " - Par ", par)

	if scoring_manager:
		scoring_manager.start_hole(par)

	hole_started.emit(hole_num, par)


func _on_hole_completed(
	strokes: int, par: int, score_name: String,
) -> void:
	print(
		"Hole completed! Score: ", score_name,
		" (", strokes, " strokes on par ", par, ")",
	)
	current_hole_index += 1
	# Flow continues via Main._on_next_hole_requested
	# → upgrade screen → advance_to_next_hole()


## Called by Main after the upgrade screen is dismissed.
func advance_to_next_hole() -> void:
	start_next_hole()


func complete_course() -> void:
	print("Course completed!")
	if scoring_manager:
		var total_par: int = get_total_par()
		course_completed.emit(
			scoring_manager.total_score, total_par,
		)


func get_total_par() -> int:
	var total: int = 0
	for par: int in hole_pars:
		total += par
	return total


func get_current_hole_number() -> int:
	return current_hole_index + 1


func get_current_par() -> int:
	if current_hole_index < hole_pars.size():
		return hole_pars[current_hole_index]
	return 3
