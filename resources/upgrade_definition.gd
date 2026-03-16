## UpgradeDefinition — data resource describing one roguelike upgrade option.
##
## Designers create .tres files of this type (Project → New Resource → UpgradeDefinition)
## and drag them into UpgradeRegistry.upgrade_pool in the Inspector.
##
## Adding a new upgrade:
##   1. Create a new .tres in res://resources/upgrades/
##   2. Fill in id, display_name, description, rarity, min_meta_level.
##   3. Add one or more UpgradeEffect sub-resources to the effects array.
##   4. Add the .tres to UpgradeRegistry.upgrade_pool.
class_name UpgradeDefinition
extends Resource

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
}

@export var id: String = ""
@export var display_name: String = "Unnamed Upgrade"
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
## Minimum meta-progression level required for this upgrade to appear in the pool.
## Level 0 = always available. See MetaProgression for thresholds.
@export var min_meta_level: int = 0
@export var effects: Array[UpgradeEffect] = []


## Applies all effects to the given PlayerState and records the upgrade id.
func apply(player: PlayerState) -> void:
	for effect: UpgradeEffect in effects:
		match effect.stat:
			UpgradeEffect.Stat.POWER:
				if effect.operation == UpgradeEffect.Operation.MULTIPLY:
					player.power_multiplier *= effect.value
				else:
					player.power_multiplier += effect.value
			UpgradeEffect.Stat.FRICTION:
				if effect.operation == UpgradeEffect.Operation.MULTIPLY:
					player.friction_modifier *= effect.value
				else:
					player.friction_modifier += effect.value
			UpgradeEffect.Stat.BOUNCE:
				if effect.operation == UpgradeEffect.Operation.MULTIPLY:
					player.bounce_modifier *= effect.value
				else:
					player.bounce_modifier += effect.value
			UpgradeEffect.Stat.ACCURACY:
				if effect.operation == UpgradeEffect.Operation.MULTIPLY:
					player.accuracy *= effect.value
				else:
					player.accuracy += effect.value
				player.accuracy = clampf(player.accuracy, 0.0, 1.0)
			UpgradeEffect.Stat.GRAVITY:
				if effect.operation == UpgradeEffect.Operation.MULTIPLY:
					player.gravity_scale *= effect.value
				else:
					player.gravity_scale += effect.value
	player.applied_upgrade_ids.append(id)


## Returns a short human-readable string summarising all stat changes (shown on the card).
func get_effects_summary() -> String:
	var parts: Array[String] = []
	for effect: UpgradeEffect in effects:
		var stat_name: String = (UpgradeEffect.Stat.keys()[effect.stat] as String).capitalize()
		if effect.operation == UpgradeEffect.Operation.MULTIPLY:
			var pct := int(round((effect.value - 1.0) * 100.0))
			var sign_str := "+" if pct >= 0 else ""
			parts.append("%s%d%% %s" % [sign_str, pct, stat_name])
		else:
			var sign_str := "+" if effect.value >= 0 else ""
			parts.append("%s%.1f %s" % [sign_str, effect.value, stat_name])
	return "\n".join(parts)
