extends Node3D

@onready var scoring_manager = $ScoringManager
@onready var score_ui = $UICanvas/ScoreUI

func _ready():
	# connect ui to scoring manager
	score_ui.setup(scoring_manager)
	
	scoring_manager.start_hole(3)
