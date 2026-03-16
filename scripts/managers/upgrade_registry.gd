## UpgradeRegistry — holds the full pool of available upgrades.
##
## Registered as an Autoload named "UpgradeRegistry" in Project Settings.
##
## To add a new upgrade: just drop a .tres file into res://resources/upgrades/.
## This registry auto-discovers all files in that folder on startup.
##
## Rarity weights control how often each tier appears when rolling choices:
##   Common   — 60%
##   Uncommon — 30%
##   Rare     — 10%
extends Node

const UPGRADES_DIR := "res://resources/upgrades/"

var upgrade_pool: Array[UpgradeDefinition] = []


func _ready() -> void:
	_load_upgrades()


func _load_upgrades() -> void:
	upgrade_pool.clear()
	var dir := DirAccess.open(UPGRADES_DIR)
	if dir == null:
		push_warning("UpgradeRegistry: folder not found — %s" % UPGRADES_DIR)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := UPGRADES_DIR + file_name
			var res: Resource = load(path)
			var def := res as UpgradeDefinition
			if def != null:
				upgrade_pool.append(def)
			else:
				push_warning("UpgradeRegistry: skipping %s (not an UpgradeDefinition)" % path)
		file_name = dir.get_next()
	dir.list_dir_end()
	print("UpgradeRegistry: loaded %d upgrades" % upgrade_pool.size())

const RARITY_WEIGHTS: Dictionary = {
	0: 60,  # COMMON
	1: 30,  # UNCOMMON
	2: 10,  # RARE
}


## Returns `count` distinct upgrades randomly chosen from the pool,
## filtered to those available at `meta_level`, weighted by rarity.
## Pass a seeded RandomNumberGenerator for deterministic results in multiplayer.
func roll_choices(meta_level: int, count: int = 3, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	# Filter by meta level
	var available: Array = []
	for u in upgrade_pool:
		var def: UpgradeDefinition = u as UpgradeDefinition
		if def != null and def.min_meta_level <= meta_level:
			available.append(def)

	if available.is_empty():
		return []

	var results: Array = []
	var remaining: Array = available.duplicate()

	for _i in range(mini(count, remaining.size())):
		var total_weight: int = 0
		for u in remaining:
			total_weight += RARITY_WEIGHTS.get(u.rarity, 10)

		var roll: int = rng.randi_range(0, total_weight - 1)
		var cumulative: int = 0
		for j: int in range(remaining.size()):
			cumulative += RARITY_WEIGHTS.get(remaining[j].rarity, 10)
			if roll < cumulative:
				results.append(remaining[j])
				remaining.remove_at(j)
				break

	return results
