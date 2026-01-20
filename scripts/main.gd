extends Node3D

@onready var scoring_manager = $ScoringManager
@onready var score_ui = $UICanvas/ScoreUI
@onready var hole_complete_ui = $UICanvas/HoleCompleteUI
@onready var course_manager = $CourseManager
@onready var current_hole: Hole
@onready var ball = $GolfBall/RigidBody3D

func reset_ball() -> void:
	ball.global_position = Vector3(0, 1, 0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.is_simulating = false
	ball.freeze = false

func _ready():
	# connect ui to scoring manager
	score_ui.setup(scoring_manager)
	course_manager.setup(scoring_manager)

	# connect signals
	course_manager.hole_started.connect(_on_hole_started)
	course_manager.course_completed.connect(_on_course_completed)
	scoring_manager.hole_completed.connect(_on_hole_completed)
	hole_complete_ui.next_hole_requested.connect(_on_next_hole_requested)

	# begin
	course_manager.start_course()

func _on_hole_started(hole_number: int, par: int):
	print("Main: Starting hole ", hole_number, " par ", par)

	if current_hole:
		current_hole.queue_free()

	current_hole = Hole.new()
	current_hole.par = par
	current_hole.hole_number = hole_number
	add_child(current_hole)

	## -- do generate hole position here -- ##
	# position cup ahead of start for now
	# update to make this generation procedural
	var cup_position = Vector3(0, .4, -20)
	current_hole.set_cup_position(cup_position)
	## -- do generate hole position here -- ##

	# connect cup signal
	current_hole.ball_entered_cup.connect(_on_ball_entered_cup)

	# reset ball position
	reset_ball()

func _on_ball_entered_cup():
	print("Ball entered cup!")
	scoring_manager.complete_hole()

func _on_hole_completed(strokes: int, par: int, score_name: String ):
	hole_complete_ui.show_result(strokes, par, score_name)

func _on_next_hole_requested():
	# course manager will automatically start next hole via signal
	pass

func _on_course_completed(total_strokes: int, total_par: int):
	print("Course completed! Total: ", total_strokes, " Par: ", total_par)
	# show final score (do this later)
