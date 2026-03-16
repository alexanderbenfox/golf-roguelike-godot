## ScorecardUI — running scorecard showing all holes played.
##
## Displayed between holes (on the hole complete and upgrade screens)
## and toggleable during play. Shows hole number, par, strokes, and
## score name for each completed hole plus a running total.
class_name ScorecardUI
extends PanelContainer

var _rows: Array[Dictionary] = []
var _vbox: VBoxContainer
var _total_label: Label


func _ready() -> void:
	# Panel styling
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	add_theme_stylebox_override("panel", style)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	add_child(_vbox)

	# Header
	var header := _make_row("Hole", "Par", "Strokes", "Score")
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_vbox.add_child(header)

	# Separator
	var sep := HSeparator.new()
	_vbox.add_child(sep)

	# Total label at the bottom
	_total_label = Label.new()
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 16)
	_total_label.add_theme_color_override(
		"font_color", Color(1.0, 1.0, 0.7)
	)

	# Anchor to top-right
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -220.0
	offset_top = 10.0
	offset_right = -10.0

	custom_minimum_size = Vector2(210.0, 0.0)
	hide()


func add_hole_result(
	hole_number: int, par: int, strokes: int, score_name: String
) -> void:
	var row_data := {
		"hole": hole_number,
		"par": par,
		"strokes": strokes,
		"score_name": score_name,
	}
	_rows.append(row_data)

	# Color strokes based on score
	var diff: int = strokes - par
	var color := Color.WHITE
	if diff < 0:
		color = Color(0.3, 1.0, 0.4)
	elif diff > 0:
		color = Color(1.0, 0.4, 0.3)

	var row := _make_row(
		str(hole_number),
		str(par),
		str(strokes),
		score_name,
	)
	row.add_theme_color_override("font_color", color)

	# Insert before the total label (or at the end of vbox if no total yet)
	if _total_label.get_parent() == _vbox:
		_vbox.move_child(
			row, _total_label.get_index()
		)
	else:
		_vbox.add_child(row)

	_update_total()


func _update_total() -> void:
	var total_strokes: int = 0
	var total_par: int = 0
	for row: Dictionary in _rows:
		total_strokes += row["strokes"] as int
		total_par += row["par"] as int

	var diff: int = total_strokes - total_par
	var diff_str: String = ""
	if diff > 0:
		diff_str = " (+%d)" % diff
	elif diff < 0:
		diff_str = " (%d)" % diff

	_total_label.text = "Total: %d%s" % [total_strokes, diff_str]

	if _total_label.get_parent() != _vbox:
		var sep := HSeparator.new()
		_vbox.add_child(sep)
		_vbox.add_child(_total_label)


func show_scorecard() -> void:
	show()


func hide_scorecard() -> void:
	hide()


func _make_row(
	col1: String, col2: String, col3: String, col4: String
) -> Label:
	var label := Label.new()
	label.text = "%-6s %-5s %-8s %s" % [col1, col2, col3, col4]
	label.add_theme_font_size_override("font_size", 14)
	return label
