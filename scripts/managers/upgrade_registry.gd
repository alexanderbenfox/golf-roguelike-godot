## UpgradeRegistry — holds the full pool of available upgrades.
##
## Registered as an Autoload named "UpgradeRegistry" in Project Settings.
##
## The upgrade pool is configured in the editor on the Main scene node via
## its `upgrade_pool` export. Call `set_pool()` at startup to populate
## the registry. Each UpgradeDefinition has an `enabled` flag — disabled
## upgrades are excluded from rolls.
##
## Rarity weights control how often each tier appears when rolling choices:
##   Common   — 60%
##   Uncommon — 30%
##   Rare     — 10%
extends Node

var upgrade_pool: Array[UpgradeDefinition] = []


## Called by Main to provide the editor-configured upgrade list.
func set_pool(pool: Array[UpgradeDefinition]) -> void:
	upgrade_pool.clear()
	for def: UpgradeDefinition in pool:
		if def != null:
			upgrade_pool.append(def)
	print("UpgradeRegistry: received %d upgrades" % upgrade_pool.size())

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

	# Filter by enabled flag and meta level
	var available: Array = []
	for u in upgrade_pool:
		var def: UpgradeDefinition = u as UpgradeDefinition
		if def != null and def.enabled and def.min_meta_level <= meta_level:
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
