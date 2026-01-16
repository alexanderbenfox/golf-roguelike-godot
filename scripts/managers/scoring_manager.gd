class_name ScoringManager
extends Node

# events
signal stroke_taken(stroke_count: int)
signal hole_completed(strokes: int, par: int, score_name: String)

var current_strokes: int = 0
var current_par: int = 3
var total_score: int = 0 # total strokes across all holes
var holes_completed: int = 0

func start_hole(par: int):
	current_par = par
	current_strokes = 0
	stroke_taken.emit(current_strokes)
	
func add_stroke():
	current_strokes += 1
	stroke_taken.emit(current_strokes)
	
func complete_hole():
	total_score += current_strokes
	holes_completed += 1
	
	var score_name = get_score_name(current_strokes, current_par)
	hole_completed.emit(current_strokes, current_par, score_name)
	
func get_score_name(strokes: int, par: int) -> String:
	var diff = strokes - par
	match diff:
		-4: return "Condor"
		-3: return "Albatross"
		-2: return "Eagle"
		-1: return "Birdie"
		0: return "Par"
		1: return "Bogey"
		2: return "Double Bogey"
		3: return "Triple Bogey"
		_:
			if diff > 3:
				return "+" + str(diff)
			else:
				return str(diff)

func get_score_relative_to_par() -> int:
	return current_strokes - current_par
	
func get_total_relative_to_par(total_par: int) -> int:
	return total_score - total_par
	
func reset_round():
	current_strokes = 0
	current_par = 3
	total_score = 0
	holes_completed = 0
	
