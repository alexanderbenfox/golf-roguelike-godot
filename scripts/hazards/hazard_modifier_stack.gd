## HazardModifierStack — runtime overrides for hazard parameters.
##
## Roguelike upgrade cards push HazardModifiers onto this stack.
## At hole build time, ProceduralHole applies these to each hazard's
## descriptor before calling setup().
##
## Modifiers can target a specific hazard type by name, or all hazards
## when target_hazard is empty.
class_name HazardModifierStack
extends RefCounted


class HazardModifier:
	extends RefCounted
	## Target hazard name (e.g. &"rock_slide"). Empty = affects all hazards.
	var target_hazard: StringName = &""
	## Parameter to modify: &"intensity", &"cycle_period",
	## &"active_duration", &"effect_radius"
	var param: StringName = &"intensity"
	## 0 = MULTIPLY, 1 = ADD (mirrors UpgradeEffect.Operation)
	var operation: int = 0
	var value: float = 1.0
	## Number of holes remaining. -1 = rest of run.
	var holes_remaining: int = -1


var modifiers: Array[HazardModifier] = []


func add_modifier(mod: HazardModifier) -> void:
	modifiers.append(mod)


## Get the effective value of a hazard parameter after applying all
## matching modifiers.
func get_effective_value(
	hazard_name: StringName,
	param: StringName,
	base_value: float,
) -> float:
	var value := base_value
	for mod: HazardModifier in modifiers:
		if mod.holes_remaining == 0:
			continue
		if mod.param != param:
			continue
		if mod.target_hazard != &"" and mod.target_hazard != hazard_name:
			continue
		if mod.operation == 0:  # MULTIPLY
			value *= mod.value
		else:  # ADD
			value += mod.value
	return value


## Call at the start of each hole to decrement durations and expire modifiers.
func tick_hole() -> void:
	for mod: HazardModifier in modifiers:
		if mod.holes_remaining > 0:
			mod.holes_remaining -= 1
	modifiers = modifiers.filter(
		func(m: HazardModifier) -> bool: return m.holes_remaining != 0
	)
