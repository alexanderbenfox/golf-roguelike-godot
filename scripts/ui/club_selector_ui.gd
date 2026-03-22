## ClubSelectorUI — bottom-center HUD showing the selected club name and info.
##
## Shows club name with left/right arrows, approximate range, and distance to pin.
class_name ClubSelectorUI
extends Control

var _bg_panel: Panel
var _club_name_label: Label
var _info_label: Label
var _left_arrow: Label
var _right_arrow: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Background panel
	_bg_panel = Panel.new()
	_bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.06, 0.06, 0.6)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	_bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(_bg_panel)

	# Left arrow
	_left_arrow = Label.new()
	_left_arrow.text = "<"
	_left_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left_arrow.add_theme_font_size_override("font_size", 20)
	_left_arrow.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.6))
	_left_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_panel.add_child(_left_arrow)

	# Club name
	_club_name_label = Label.new()
	_club_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_club_name_label.add_theme_font_size_override("font_size", 22)
	_club_name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_club_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_panel.add_child(_club_name_label)

	# Right arrow
	_right_arrow = Label.new()
	_right_arrow.text = ">"
	_right_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_arrow.add_theme_font_size_override("font_size", 20)
	_right_arrow.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.6))
	_right_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_panel.add_child(_right_arrow)

	# Info line (range + distance to pin)
	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.7))
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_panel.add_child(_info_label)

	_layout()
	visible = false


func _layout() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var panel_w: float = 260.0
	var panel_h: float = 56.0
	var margin_bottom: float = 12.0

	_bg_panel.position = Vector2(
		(vp_size.x - panel_w) * 0.5,
		vp_size.y - margin_bottom - panel_h,
	)
	_bg_panel.size = Vector2(panel_w, panel_h)

	_left_arrow.position = Vector2(8, 6)
	_left_arrow.size = Vector2(20, 24)

	_club_name_label.position = Vector2(28, 4)
	_club_name_label.size = Vector2(panel_w - 56, 28)

	_right_arrow.position = Vector2(panel_w - 28, 6)
	_right_arrow.size = Vector2(20, 24)

	_info_label.position = Vector2(8, 34)
	_info_label.size = Vector2(panel_w - 16, 18)


func show_selector() -> void:
	visible = true


func hide_selector() -> void:
	visible = false


func update_club(club: ClubDefinition, distance_to_pin: float) -> void:
	if not club:
		_club_name_label.text = "—"
		_info_label.text = ""
		return
	_club_name_label.text = club.display_name

	var range_text: String = "~%dm" % int(club.suggest_max_distance)
	if club.suggest_max_distance >= 999.0:
		range_text = "Max range"

	if distance_to_pin > 0.0:
		_info_label.text = "%s  |  %dm to pin" % [range_text, int(distance_to_pin)]
	else:
		_info_label.text = range_text


func set_arrows_visible(show_left: bool, show_right: bool) -> void:
	_left_arrow.visible = show_left
	_right_arrow.visible = show_right
