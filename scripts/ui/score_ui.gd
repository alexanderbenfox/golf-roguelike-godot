class_name ScoreUI
extends Control

@export var stroke_label: Label
@export var par_label: Label
@export var score_label: Label

var scoring_manager: ScoringManager

func _ready():
	pass
	
func setup(manager: ScoringManager):
	scoring_manager = manager
	scoring_manager.stroke_taken.connect(_on_stroke_taken)
	
func _on_stroke_taken(strokes: int):
	update_display()
	
func update_display():
	if not scoring_manager:
		return
	
	# show strokes
	stroke_label.text = "Strokes: " + str(scoring_manager.current_strokes)
	
	# show par
	par_label.text = "Par: " + str(scoring_manager.current_par)
	
	# show score relative to par
	var relative = scoring_manager.get_score_relative_to_par()
	if relative == 0:
		score_label.text = "E" # even par
	elif relative > 0:
		score_label.text = "+" + str(relative)
		score_label.modulate = Color.RED
	else:
		score_label.text = str(relative)
		score_label.modulate = Color.GREEN
