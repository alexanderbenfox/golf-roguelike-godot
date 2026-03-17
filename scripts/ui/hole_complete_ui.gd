class_name HoleCompleteUI
extends Control

@onready var result_label: Label = $Panel/VBoxContainer/ResultLabel
@onready var strokes_label: Label = $Panel/VBoxContainer/StrokesLabel
@onready var next_button: Button = $Panel/VBoxContainer/NextButton

signal next_hole_requested

func _ready() -> void:
	hide()
	if next_button:
		next_button.pressed.connect(_on_next_button_pressed)

func show_result(strokes: int, par: int, score_name: String) -> void:
	result_label.text = score_name + "!"
	strokes_label.text = str(strokes) + " strokes on par " + str(par)

	if strokes < par:
		result_label.modulate = Color.GREEN
	elif strokes == par:
		result_label.modulate = Color.YELLOW
	else:
		result_label.modulate = Color.RED

	show()

func set_button_text(text: String) -> void:
	if next_button:
		next_button.text = text


func _on_next_button_pressed() -> void:
	next_button.text = "Next Hole"
	hide()
	next_hole_requested.emit()
