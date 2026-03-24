## AngleDisplay — small HUD element showing the current launch angle in degrees.
##
## Positioned bottom-right. Shows the angle value and Q/E key hints.
class_name AngleDisplay
extends Control

var _angle_label: Label
var _hint_label: Label
var _bg_panel: Panel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Background panel
	_bg_panel = Panel.new()
	_bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.184, 0.106, 0.067, 0.75)  # BARK
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	bg_style.border_color = Color(0.376, 0.424, 0.220)     # OLIVE
	bg_style.set_border_width_all(1)
	_bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(_bg_panel)

	# Angle value
	_angle_label = Label.new()
	_angle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_angle_label.add_theme_font_size_override("font_size", 24)
	_angle_label.add_theme_color_override("font_color", Color(0.941, 0.918, 0.847, 0.9))  # PARCHMENT
	_angle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_panel.add_child(_angle_label)

	# Key hint
	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.659, 0.733, 0.800, 0.65))  # SKY
	_hint_label.text = "Q / E"
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_panel.add_child(_hint_label)

	_layout()
	visible = false


func _layout() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var panel_w: float = 80.0
	var panel_h: float = 56.0
	var margin_right: float = 24.0
	var margin_bottom: float = 80.0

	_bg_panel.position = Vector2(
		vp_size.x - margin_right - panel_w,
		vp_size.y - margin_bottom - panel_h,
	)
	_bg_panel.size = Vector2(panel_w, panel_h)

	_angle_label.position = Vector2(0, 4)
	_angle_label.size = Vector2(panel_w, 28)

	_hint_label.position = Vector2(0, 32)
	_hint_label.size = Vector2(panel_w, 18)


func show_display() -> void:
	visible = true


func hide_display() -> void:
	visible = false


func update_angle(angle_deg: float) -> void:
	_angle_label.text = "%d" % int(angle_deg) + "\u00b0"
