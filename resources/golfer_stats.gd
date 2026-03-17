## GolferStats — editor-configurable starting stats for a player.
##
## Assign a .tres of this type in the Inspector to set the base stats
## that a player begins each run with. Upgrades modify these during play.
## These can also be shown to the player in a stats UI.
class_name GolferStats
extends Resource

@export_group("Power")
## Base power multiplier. 1.0 = default shot distance.
@export_range(0.1, 3.0, 0.05) var power_multiplier: float = 1.0

@export_group("Ball Control")
## Ground friction modifier. Higher = ball stops sooner.
@export_range(0.1, 3.0, 0.05) var friction_modifier: float = 1.0
## Surface bounce modifier. Higher = bouncier.
@export_range(0.1, 3.0, 0.05) var bounce_modifier: float = 1.0

@export_group("Gravity")
## Gravity multiplier. Lower = floatier shots, higher = heavier ball.
@export_range(0.1, 15.0, 0.05) var gravity_scale: float = 3.0

@export_group("Accuracy")
## Shot accuracy. 0.0 = max spread, 1.0 = perfect aim.
@export_range(0.0, 1.0, 0.05) var accuracy: float = 0.7


## Applies these starting stats onto a PlayerState, resetting modifiers.
func apply_to(player: PlayerState) -> void:
	player.power_multiplier = power_multiplier
	player.friction_modifier = friction_modifier
	player.bounce_modifier = bounce_modifier
	player.gravity_scale = gravity_scale
	player.accuracy = accuracy
