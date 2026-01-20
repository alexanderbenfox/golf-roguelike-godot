class_name CourseManager
extends Node

signal hole_started(hole_number: int, par: int)
signal course_completed(totals_strokes: int, total_par: int)

@export var holes_in_course: int = 9
var current_hole_index: int = 0
var hole_pars: Array[int] = []

var scoring_manager: ScoringManager
var current_hole: Hole

func _ready() -> void:
    generate_course()

func generate_course():
    # generate random pars for each hole
    hole_pars.clear()
    for i in range(holes_in_course):
        var par = randi_range(3, 5)
        hole_pars.append(par)

func setup(manager : ScoringManager):
    scoring_manager = manager
    scoring_manager.hole_completed.connect(_on_hole_completed)

func start_course():
    current_hole_index = 0
    start_next_hole()

func start_next_hole():
    if current_hole_index >= holes_in_course:
        complete_course()
        return

    var par = hole_pars[current_hole_index]
    var hole_num = current_hole_index + 1

    print("Starting hole ", hole_num, " - Par ", par)

    if scoring_manager:
        scoring_manager.start_hole(par)

    hole_started.emit(hole_num, par)

func _on_hole_completed(strokes: int, par: int, score_name: String):
    print("Hole completed! Score: ", score_name, " (", strokes, " strokes on par ", par, ")")

    current_hole_index += 1

    #short delay before next hole
    await get_tree().create_timer(2.0).timeout
    start_next_hole()

func complete_course():
    print("Course completed!")
    if scoring_manager:
        var total_par = get_total_par()
        course_completed.emit(scoring_manager.total_score, total_par)

func get_total_par() -> int:
    var total = 0
    for par in hole_pars:
        total += par
    return total

func get_current_hole_number() -> int:
    return current_hole_index + 1

func get_current_par() -> int:
    if current_hole_index < hole_pars.size():
        return hole_pars[current_hole_index]
    return 3
