## HoleTracker — 2D screen-space indicator pointing toward the cup.
##
## Projects the cup's world position into screen space and draws an indicator.
## When the cup is off-screen, the indicator pins to the screen edge and points
## toward it. Fades out as the player gets close.
class_name HoleTracker
extends Control

const ICON_SIZE: float = 44.0
const EDGE_MARGIN: float = 40.0
const FADE_START_DIST: float = 30.0  ## distance (m) where fade begins
const FADE_END_DIST: float = 8.0    ## distance (m) where fully invisible
const LABEL_OFFSET_Y: float = 20.0

var _icon: Control
var _dist_label: Label

var cup_world_position: Vector3 = Vector3.ZERO
var ball_world_position: Vector3 = Vector3.ZERO
var _camera: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Diamond icon (drawn procedurally)
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(ICON_SIZE * 2.0, ICON_SIZE * 2.0)
	_icon.size = Vector2(ICON_SIZE * 2.0, ICON_SIZE * 2.0)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	add_child(_icon)

	# Distance label below icon
	_dist_label = Label.new()
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dist_label.add_theme_font_size_override("font_size", 15)
	_dist_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	_dist_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dist_label)

	visible = false


func setup(cam: Camera3D) -> void:
	_camera = cam


func update_positions(cup_pos: Vector3, ball_pos: Vector3) -> void:
	cup_world_position = cup_pos
	ball_world_position = ball_pos


func _process(_delta: float) -> void:
	if not _camera or cup_world_position == Vector3.ZERO:
		visible = false
		return

	var dist_xz: float = Vector3(
		ball_world_position.x - cup_world_position.x, 0.0,
		ball_world_position.z - cup_world_position.z
	).length()

	# Fade based on distance
	if dist_xz < FADE_END_DIST:
		visible = false
		return

	visible = true
	var alpha: float = 1.0
	if dist_xz < FADE_START_DIST:
		alpha = clampf(
			(dist_xz - FADE_END_DIST) / (FADE_START_DIST - FADE_END_DIST),
			0.0, 1.0
		)
	modulate.a = alpha

	# Project cup position to screen
	var vp_size: Vector2 = get_viewport_rect().size
	var screen_pos: Vector2 = _camera.unproject_position(cup_world_position)

	# Check if the cup is behind the camera
	var cam_fwd: Vector3 = -_camera.global_transform.basis.z
	var to_cup: Vector3 = cup_world_position - _camera.global_position
	var is_behind: bool = cam_fwd.dot(to_cup) < 0.0

	if is_behind:
		# Flip to the opposite side of the screen
		screen_pos = vp_size * 0.5 - (screen_pos - vp_size * 0.5)

	# Clamp to screen edges with margin
	var on_screen: bool = (
		not is_behind
		and screen_pos.x >= EDGE_MARGIN
		and screen_pos.x <= vp_size.x - EDGE_MARGIN
		and screen_pos.y >= EDGE_MARGIN
		and screen_pos.y <= vp_size.y - EDGE_MARGIN
	)

	if not on_screen:
		# Pin to edge: find intersection with screen rectangle
		var center: Vector2 = vp_size * 0.5
		var direction: Vector2 = (screen_pos - center).normalized()
		if direction.length_squared() < 0.001:
			direction = Vector2.UP

		# Scale direction to hit the margin-inset rectangle
		var half_w: float = vp_size.x * 0.5 - EDGE_MARGIN
		var half_h: float = vp_size.y * 0.5 - EDGE_MARGIN
		var scale_x: float = absf(half_w / direction.x) if absf(direction.x) > 0.001 else 99999.0
		var scale_y: float = absf(half_h / direction.y) if absf(direction.y) > 0.001 else 99999.0
		var edge_scale: float = minf(scale_x, scale_y)
		screen_pos = center + direction * edge_scale

	# Position the icon centered on screen_pos
	_icon.position = screen_pos - _icon.size * 0.5
	_icon.queue_redraw()

	# Distance label
	_dist_label.text = "%dm" % int(dist_xz)
	_dist_label.position = Vector2(
		screen_pos.x - 40.0,
		screen_pos.y + ICON_SIZE * 0.5 + 6.0,
	)
	_dist_label.size = Vector2(80.0, 22.0)


func _draw_icon() -> void:
	var cx: float = _icon.size.x * 0.5
	var cy: float = _icon.size.y * 0.5
	var r: float = ICON_SIZE * 0.5
	var segments: int = 32

	# White background disc for contrast
	var bg_points: PackedVector2Array = PackedVector2Array()
	var bg_r: float = r + 4.0
	for i: int in range(segments):
		var angle: float = float(i) / float(segments) * TAU
		bg_points.append(Vector2(cx + cos(angle) * bg_r, cy + sin(angle) * bg_r))
	_icon.draw_colored_polygon(bg_points, Color(1.0, 1.0, 1.0, 0.75))

	# Dark inner disc
	var dark_points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments):
		var angle: float = float(i) / float(segments) * TAU
		dark_points.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
	_icon.draw_colored_polygon(dark_points, Color(0.1, 0.1, 0.1, 0.85))

	# Gold outer ring
	var ring_points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments + 1):
		var angle: float = float(i) / float(segments) * TAU
		ring_points.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
	_icon.draw_polyline(ring_points, Color(1.0, 0.85, 0.2, 1.0), 3.0)

	# Inner filled gold circle
	var inner_points: PackedVector2Array = PackedVector2Array()
	var inner_r: float = r * 0.3
	for i: int in range(segments):
		var angle: float = float(i) / float(segments) * TAU
		inner_points.append(Vector2(
			cx + cos(angle) * inner_r,
			cy + sin(angle) * inner_r,
		))
	_icon.draw_colored_polygon(inner_points, Color(1.0, 0.85, 0.2, 0.8))

	# Flag pole line
	_icon.draw_line(
		Vector2(cx, cy - r * 0.3),
		Vector2(cx, cy - r * 1.1),
		Color(1.0, 1.0, 1.0, 0.9), 1.5,
	)
	# Small flag triangle
	_icon.draw_colored_polygon(
		PackedVector2Array([
			Vector2(cx, cy - r * 1.1),
			Vector2(cx + r * 0.5, cy - r * 0.85),
			Vector2(cx, cy - r * 0.65),
		]),
		Color(1.0, 0.3, 0.2, 0.85),
	)
