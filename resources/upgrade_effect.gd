## UpgradeEffect — a single stat modification bundled inside an UpgradeDefinition.
##
## Designers create these as inline sub-resources inside an UpgradeDefinition .tres file.
## Each UpgradeDefinition can have one or more effects (e.g. a rare upgrade might buff
## both power and bounce simultaneously).
class_name UpgradeEffect
extends Resource

enum Stat {
	POWER,    ## Scales how far the ball travels per shot.
	FRICTION, ## Scales ground friction (higher = ball stops sooner).
	BOUNCE,   ## Scales how much the ball bounces off surfaces.
	ACCURACY, ## Scales shot accuracy (higher = tighter spread).
	GRAVITY,  ## Scales gravity on the ball (lower = floatier, longer hang time).
}

enum Operation {
	MULTIPLY, ## player_stat *= value  (use values like 1.2 for +20%, 0.8 for -20%)
	ADD,      ## player_stat += value  (flat addition; use sparingly)
}

@export var stat: Stat = Stat.POWER
@export var operation: Operation = Operation.MULTIPLY
@export var value: float = 1.0
