## WindIndicator — HUD element showing wind direction and speed.
##
## Displays a rotatable arrow and speed label. Hidden when wind is zero.
## Add as a child of the UI canvas; call update_wind() each hole.
class_name WindIndicator
extends Control

var _arrow: Control
var _speed_label: Label
var _dir_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(110, 110)

	# Container positioned top-right, shifted down and left
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -146.0
	offset_top = 40.0
	offset_right = -36.0
	offset_bottom = 150.0

	# Arrow triangle (drawn procedurally)
	_arrow = Control.new()
	_arrow.custom_minimum_size = Vector2(56, 56)
	_arrow.size = Vector2(56, 56)
	_arrow.position = Vector2(27, 10)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)

	# Speed label
	_speed_label = Label.new()
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.add_theme_font_size_override("font_size", 20)
	_speed_label.add_theme_color_override("font_color", Color(0.941, 0.918, 0.847, 0.9))  # PARCHMENT
	_speed_label.position = Vector2(0, 64)
	_speed_label.size = Vector2(110, 24)
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_speed_label)

	# Direction label (N/S/E/W)
	_dir_label = Label.new()
	_dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dir_label.add_theme_font_size_override("font_size", 15)
	_dir_label.add_theme_color_override("font_color", Color(0.553, 0.522, 0.337, 0.7))  # SAND
	_dir_label.position = Vector2(0, 88)
	_dir_label.size = Vector2(110, 20)
	_dir_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dir_label)

	visible = false


func update_wind(wind: Vector3) -> void:
	var speed: float = Vector2(wind.x, wind.z).length()
	if speed < 0.1:
		visible = false
		return
	visible = true

	# Rotate arrow to point in wind direction
	# atan2(x, z) gives angle from +Z axis; UI rotation is clockwise from up
	var angle: float = atan2(wind.x, wind.z)
	_arrow.rotation = angle
	_arrow.queue_redraw()

	_speed_label.text = "%.1f m/s" % speed
	_dir_label.text = _wind_compass(angle)


func _draw_arrow() -> void:
	var center := Vector2(28, 28)
	var size_f: float = 22.0
	# Triangle pointing up (rotation handled by Control.rotation)
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0, -size_f),        # tip
		center + Vector2(-size_f * 0.5, size_f * 0.6),  # bottom-left
		center + Vector2(size_f * 0.5, size_f * 0.6),   # bottom-right
	])
	var color := Color(0.659, 0.733, 0.800, 0.85)  # SKY
	_arrow.draw_colored_polygon(points, color)
	# Outline for visibility
	_arrow.draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[0]]),
		Color(0.941, 0.918, 0.847, 0.5), 1.5,  # PARCHMENT
	)


static func _wind_compass(angle_rad: float) -> String:
	# angle_rad: 0 = +Z (South in typical golf), PI/2 = +X (East)
	var deg: float = rad_to_deg(angle_rad)
	if deg < 0:
		deg += 360.0
	# Map to compass: 0° = S, 90° = E, 180° = N, 270° = W
	# (because +Z is south, +X is east in Godot's coordinate system)
	if deg < 22.5 or deg >= 337.5:
		return "S"
	if deg < 67.5:
		return "SE"
	if deg < 112.5:
		return "E"
	if deg < 157.5:
		return "NE"
	if deg < 202.5:
		return "N"
	if deg < 247.5:
		return "NW"
	if deg < 292.5:
		return "W"
	return "SW"
