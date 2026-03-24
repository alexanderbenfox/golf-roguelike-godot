class_name HoleCompleteUI
extends Control

@onready var result_label: Label = $Panel/VBoxContainer/ResultLabel
@onready var strokes_label: Label = $Panel/VBoxContainer/StrokesLabel
@onready var next_button: Button = $Panel/VBoxContainer/NextButton

signal next_hole_requested

func _ready() -> void:
	# Style the panel background
	var panel := $Panel as Panel
	if panel:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.184, 0.106, 0.067, 0.92)  # BARK
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = Color(0.376, 0.424, 0.220)    # OLIVE
		style.content_margin_left   = 24
		style.content_margin_right  = 24
		style.content_margin_top    = 20
		style.content_margin_bottom = 20
		panel.add_theme_stylebox_override("panel", style)

	if strokes_label:
		strokes_label.add_theme_color_override("font_color", Color(0.553, 0.522, 0.337))  # SAND

	if next_button:
		UITheme.apply_button_theme(next_button)
		next_button.pressed.connect(_on_next_button_pressed)

	hide()

func show_result(strokes: int, par: int, score_name: String) -> void:
	result_label.text = score_name + "!"
	strokes_label.text = str(strokes) + " strokes on par " + str(par)

	if strokes < par:
		result_label.modulate = Color(0.333, 0.510, 0.153)  # GRASS
	elif strokes == par:
		result_label.modulate = Color(0.553, 0.522, 0.337)  # SAND
	else:
		result_label.modulate = Color(0.412, 0.173, 0.173)  # CLAY

	show()

func set_button_text(text: String) -> void:
	if next_button:
		next_button.text = text


func _on_next_button_pressed() -> void:
	next_button.text = "Next Hole"
	hide()
	next_hole_requested.emit()
