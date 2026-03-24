## AccuracyTimingBar — horizontal bar for the accuracy phase of the three-press swing.
##
## Appears after power is locked. A bright sweeping indicator bounces across the
## bar; the player presses shoot to stop it in the sweet spot. The indicator has
## a colored arrow above/below the bar and a glow that changes color based on
## which zone it's in (green = sweet spot, yellow = OK, red = miss).
class_name AccuracyTimingBar
extends Control

const BAR_WIDTH: float = 500.0
const BAR_HEIGHT: float = 44.0
const BAR_MARGIN_BOTTOM: float = 100.0
const BORDER_WIDTH: float = 2.5
const INDICATOR_WIDTH: float = 4.0
const GLOW_WIDTH: float = 24.0
const ARROW_SIZE: float = 14.0

var _draw_node: Control
var _title_label: Label
var _result_label: Label

var _bar_rect: Rect2
var _indicator_percent: float = 0.5
var _sweet_spot: Vector2 = Vector2(0.4, 0.6)
var _perfect: Vector2 = Vector2(0.48, 0.52)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Single custom-draw node for the entire bar + indicator + arrows
	_draw_node = Control.new()
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_draw_node.draw.connect(_on_draw)
	add_child(_draw_node)

	# "ACCURACY — CLICK TO LOCK" title above the bar
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.941, 0.918, 0.847, 0.9))  # PARCHMENT
	_title_label.text = "ACCURACY — CLICK TO LOCK"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	# Result flash label (Perfect! / Good / OK / Miss)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 28)
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label.visible = false
	add_child(_result_label)

	_layout()
	visible = false


func _layout() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var bar_x: float = (vp_size.x - BAR_WIDTH) * 0.5
	var bar_y: float = vp_size.y - BAR_MARGIN_BOTTOM - BAR_HEIGHT
	_bar_rect = Rect2(bar_x, bar_y, BAR_WIDTH, BAR_HEIGHT)

	_title_label.position = Vector2(bar_x, bar_y - 32)
	_title_label.size = Vector2(BAR_WIDTH, 26)

	_result_label.position = Vector2(bar_x, bar_y - 68)
	_result_label.size = Vector2(BAR_WIDTH, 34)


func show_bar() -> void:
	visible = true
	_result_label.visible = false
	_title_label.visible = true


func hide_bar() -> void:
	visible = false


## Update the sweet spot and perfect zone positions.
## sweet_spot: Vector2(lo, hi) in 0-1 range.
## perfect: Vector2(lo, hi) in 0-1 range.
func set_zones(sweet_spot: Vector2, perfect: Vector2) -> void:
	_sweet_spot = sweet_spot
	_perfect = perfect
	_draw_node.queue_redraw()


## Update the sweeping indicator position (0-1 range).
func update_indicator(percent: float) -> void:
	_indicator_percent = clampf(percent, 0.0, 1.0)
	_draw_node.queue_redraw()


## Show a brief result label (Perfect! / Good / OK / Miss).
func show_result(result: int) -> void:
	var texts: Array[String] = ["Perfect!", "Good", "OK", "Miss"]
	var colors: Array[Color] = [
		Color(0.333, 0.510, 0.153),  # GRASS   — Perfect
		Color(0.522, 0.584, 0.239),  # FERN    — Good
		Color(0.553, 0.522, 0.337),  # SAND    — OK
		Color(0.412, 0.173, 0.173),  # CLAY    — Miss
	]
	if result < 0 or result >= texts.size():
		return
	_result_label.text = texts[result]
	_result_label.add_theme_color_override("font_color", colors[result])
	_result_label.visible = true
	_title_label.visible = false

	# Auto-hide after a brief moment
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(_result_label, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		_result_label.visible = false
		_result_label.modulate.a = 1.0
	)


# -- Custom drawing -----------------------------------------------------------

func _on_draw() -> void:
	var r: Rect2 = _bar_rect
	var pad: float = BORDER_WIDTH
	var inner_x: float = r.position.x + pad
	var inner_y: float = r.position.y + pad
	var inner_w: float = r.size.x - pad * 2.0
	var inner_h: float = r.size.y - pad * 2.0

	# --- Dark background (POND) ---
	_draw_node.draw_rect(r, Color(0.043, 0.224, 0.282, 0.92))  # POND

	# --- Miss zones (red on edges) ---
	if _sweet_spot.x > 0.01:
		_draw_node.draw_rect(
			Rect2(inner_x, inner_y, _sweet_spot.x * inner_w, inner_h),
			Color(0.412, 0.173, 0.173, 0.55))  # CLAY
	if _sweet_spot.y < 0.99:
		var rx: float = inner_x + _sweet_spot.y * inner_w
		_draw_node.draw_rect(
			Rect2(rx, inner_y, (1.0 - _sweet_spot.y) * inner_w, inner_h),
			Color(0.412, 0.173, 0.173, 0.55))  # CLAY

	# --- OK zones (orange, between miss and sweet spot edges) ---
	# Narrow orange strips just outside the sweet spot
	var ok_band: float = 0.06  # 6% of bar on each side
	var ok_left_lo: float = maxf(_sweet_spot.x - ok_band, 0.0)
	var ok_left_hi: float = _sweet_spot.x
	if ok_left_hi > ok_left_lo + 0.005:
		_draw_node.draw_rect(
			Rect2(inner_x + ok_left_lo * inner_w, inner_y,
				(ok_left_hi - ok_left_lo) * inner_w, inner_h),
			Color(0.553, 0.522, 0.337, 0.40))  # SAND
	var ok_right_lo: float = _sweet_spot.y
	var ok_right_hi: float = minf(_sweet_spot.y + ok_band, 1.0)
	if ok_right_hi > ok_right_lo + 0.005:
		_draw_node.draw_rect(
			Rect2(inner_x + ok_right_lo * inner_w, inner_y,
				(ok_right_hi - ok_right_lo) * inner_w, inner_h),
			Color(0.553, 0.522, 0.337, 0.40))  # SAND

	# --- Sweet spot (green) ---
	var ss_x: float = inner_x + _sweet_spot.x * inner_w
	var ss_w: float = (_sweet_spot.y - _sweet_spot.x) * inner_w
	_draw_node.draw_rect(Rect2(ss_x, inner_y, ss_w, inner_h),
		Color(0.376, 0.424, 0.220, 0.65))  # OLIVE

	# --- Perfect zone (bright green center) ---
	var pf_x: float = inner_x + _perfect.x * inner_w
	var pf_w: float = (_perfect.y - _perfect.x) * inner_w
	_draw_node.draw_rect(Rect2(pf_x, inner_y, pf_w, inner_h),
		Color(0.333, 0.510, 0.153, 0.85))  # GRASS

	# --- Border ---
	_draw_node.draw_rect(r, Color(0.553, 0.522, 0.337, 0.75), false, BORDER_WIDTH)  # SAND

	# --- Indicator ---
	var ind_x: float = inner_x + _indicator_percent * inner_w
	var zone_color: Color = _get_zone_color(_indicator_percent)

	# Wide soft glow behind indicator
	_draw_node.draw_rect(
		Rect2(ind_x - GLOW_WIDTH * 0.5, inner_y, GLOW_WIDTH, inner_h),
		Color(zone_color.r, zone_color.g, zone_color.b, 0.25))

	# Bright indicator line
	_draw_node.draw_line(
		Vector2(ind_x, r.position.y), Vector2(ind_x, r.position.y + r.size.y),
		Color(1.0, 1.0, 1.0, 1.0), INDICATOR_WIDTH)
	# Zone-colored core line on top
	_draw_node.draw_line(
		Vector2(ind_x, inner_y + 1.0), Vector2(ind_x, inner_y + inner_h - 1.0),
		zone_color, INDICATOR_WIDTH - 1.0)

	# --- Arrow above the bar (pointing down ▼) ---
	var arrow_top: float = r.position.y - ARROW_SIZE - 3.0
	var arrow_bot: float = r.position.y - 1.0
	_draw_node.draw_colored_polygon(PackedVector2Array([
		Vector2(ind_x, arrow_bot),
		Vector2(ind_x - ARROW_SIZE * 0.6, arrow_top),
		Vector2(ind_x + ARROW_SIZE * 0.6, arrow_top),
	]), zone_color)
	_draw_node.draw_polyline(PackedVector2Array([
		Vector2(ind_x - ARROW_SIZE * 0.6, arrow_top),
		Vector2(ind_x, arrow_bot),
		Vector2(ind_x + ARROW_SIZE * 0.6, arrow_top),
		Vector2(ind_x - ARROW_SIZE * 0.6, arrow_top),
	]), Color(0.941, 0.918, 0.847, 0.7), 1.5)  # PARCHMENT

	# --- Arrow below the bar (pointing up ▲) ---
	var btri_top: float = r.position.y + r.size.y + 1.0
	var btri_bot: float = btri_top + ARROW_SIZE
	_draw_node.draw_colored_polygon(PackedVector2Array([
		Vector2(ind_x, btri_top),
		Vector2(ind_x - ARROW_SIZE * 0.6, btri_bot),
		Vector2(ind_x + ARROW_SIZE * 0.6, btri_bot),
	]), zone_color)
	_draw_node.draw_polyline(PackedVector2Array([
		Vector2(ind_x - ARROW_SIZE * 0.6, btri_bot),
		Vector2(ind_x, btri_top),
		Vector2(ind_x + ARROW_SIZE * 0.6, btri_bot),
		Vector2(ind_x - ARROW_SIZE * 0.6, btri_bot),
	]), Color(0.941, 0.918, 0.847, 0.7), 1.5)  # PARCHMENT


func _get_zone_color(percent: float) -> Color:
	if percent >= _perfect.x and percent <= _perfect.y:
		return Color(0.333, 0.510, 0.153)   # GRASS — Perfect
	elif percent >= _sweet_spot.x and percent <= _sweet_spot.y:
		return Color(0.522, 0.584, 0.239)   # FERN — Good
	else:
		# Fade from SAND to CLAY based on distance from sweet spot
		var dist: float = 0.0
		if percent < _sweet_spot.x:
			dist = (_sweet_spot.x - percent) / maxf(_sweet_spot.x, 0.01)
		else:
			dist = (percent - _sweet_spot.y) / maxf(1.0 - _sweet_spot.y, 0.01)
		dist = clampf(dist, 0.0, 1.0)
		return Color(
			lerpf(0.553, 0.412, dist),
			lerpf(0.522, 0.173, dist),
			lerpf(0.337, 0.173, dist))
