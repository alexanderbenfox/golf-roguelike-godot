## TerrainPowerMeter — vertical bar showing power level and terrain zone bands.
##
## Displays a tall vertical bar on the center-left of the screen. Zone color
## bands show what terrain the ball would land in at each power level. A bright
## indicator line shows the current power position.
##
## When the player overshoots 100%, the indicator rises above the bar, shakes,
## and the bar wobbles and glows red — signaling accuracy is degrading.
class_name TerrainPowerMeter
extends Control

const BAR_WIDTH: float = 56.0
const BAR_HEIGHT: float = 400.0
const INDICATOR_HEIGHT: float = 4.0
const OVERSHOOT_MAX_RISE: float = 40.0  ## how far above bar the indicator can go
const SHAKE_INTENSITY: float = 6.0       ## max horizontal shake pixels
const WOBBLE_INTENSITY: float = 4.0      ## max horizontal bar wobble pixels

## Zone type abbreviations for labels
const ZONE_LABELS: Dictionary = {
	0: "T",   # Tee
	1: "R",   # Rough
	2: "G",   # Green
	3: "P",   # Path
	4: "B",   # Bunker
	5: "W",   # Water
	6: "H",   # Hazard (lava)
	7: "D",   # Deep rough
}

var _bar_panel: Panel
var _indicator: ColorRect
var _zone_drawer: Control
var _power_label: Label
var _overshoot_overlay: ColorRect
var _accuracy_label: Label

## Cached terrain band data: array of {percent: float, color: Color, zone: int}
var _bands: Array[Dictionary] = []
var _indicator_percent: float = 0.0
var _is_overshooting: bool = false
var _overshoot_amount: float = 0.0
var _overshoot_time: float = 0.0

## Base positions (before wobble offsets)
var _base_bar_pos: Vector2 = Vector2.ZERO
var _base_indicator_y: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Background panel
	_bar_panel = Panel.new()
	_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.06, 0.06, 0.75)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	_bar_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(_bar_panel)

	# Zone band drawer (custom draw)
	_zone_drawer = Control.new()
	_zone_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_drawer.draw.connect(_draw_zones)
	_bar_panel.add_child(_zone_drawer)

	# Red overshoot overlay — covers the whole bar with pulsing red when overshooting
	_overshoot_overlay = ColorRect.new()
	_overshoot_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overshoot_overlay.color = Color(1.0, 0.1, 0.1, 0.0)
	_bar_panel.add_child(_overshoot_overlay)

	# Indicator line — child of self (not panel) so it can rise above the bar
	_indicator = ColorRect.new()
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator.color = Color(1.0, 1.0, 1.0, 0.95)
	add_child(_indicator)

	# Power percentage label
	_power_label = Label.new()
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.add_theme_font_size_override("font_size", 20)
	_power_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
	_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_power_label)

	# Accuracy warning label (shows below power % when overshooting)
	_accuracy_label = Label.new()
	_accuracy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_accuracy_label.add_theme_font_size_override("font_size", 14)
	_accuracy_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 0.9))
	_accuracy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_accuracy_label.visible = false
	add_child(_accuracy_label)

	_layout()
	visible = false


func _layout() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	# Center-left of screen, vertically centered
	var bar_x: float = vp_size.x * 0.25 - BAR_WIDTH * 0.5
	var bar_y: float = (vp_size.y - BAR_HEIGHT) * 0.5
	_base_bar_pos = Vector2(bar_x, bar_y)

	_bar_panel.position = _base_bar_pos
	_bar_panel.size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	var pad: float = 4.0
	_zone_drawer.position = Vector2(pad, pad)
	_zone_drawer.size = Vector2(BAR_WIDTH - pad * 2.0, BAR_HEIGHT - pad * 2.0)

	_overshoot_overlay.position = Vector2(pad, pad)
	_overshoot_overlay.size = Vector2(BAR_WIDTH - pad * 2.0, BAR_HEIGHT - pad * 2.0)

	_indicator.size = Vector2(BAR_WIDTH, INDICATOR_HEIGHT)

	_power_label.position = Vector2(bar_x, bar_y + BAR_HEIGHT + 6)
	_power_label.size = Vector2(BAR_WIDTH, 24)

	_accuracy_label.position = Vector2(bar_x - 10, bar_y + BAR_HEIGHT + 28)
	_accuracy_label.size = Vector2(BAR_WIDTH + 20, 18)


func show_meter() -> void:
	if visible:
		return
	visible = true
	_is_overshooting = false
	_overshoot_amount = 0.0
	_overshoot_overlay.color.a = 0.0
	_accuracy_label.visible = false
	_indicator.color = Color(1.0, 1.0, 1.0, 0.95)
	_bar_panel.position = _base_bar_pos


func hide_meter() -> void:
	visible = false
	_bands.clear()
	_is_overshooting = false
	_overshoot_amount = 0.0
	_bar_panel.position = _base_bar_pos


func update_power(percent: float) -> void:
	_indicator_percent = clampf(percent, 0.0, 1.0)
	# Position indicator in screen space (indicator is child of self, not panel)
	var inner_height: float = BAR_HEIGHT - 8.0
	var y: float = _base_bar_pos.y + 4.0 + inner_height * (1.0 - _indicator_percent)
	_base_indicator_y = y
	if not _is_overshooting:
		_indicator.position = Vector2(_base_bar_pos.x, y - INDICATOR_HEIGHT * 0.5)

	_power_label.text = "%d%%" % int(_indicator_percent * 100.0)


func set_overshooting(overshooting: bool, amount: float = 0.0) -> void:
	_overshoot_amount = amount
	if overshooting == _is_overshooting:
		return
	_is_overshooting = overshooting
	if overshooting:
		_overshoot_time = 0.0
		_indicator.color = Color(1.0, 0.3, 0.2, 1.0)
		_accuracy_label.text = "OVERSHOOT!"
		_accuracy_label.visible = true
	else:
		_indicator.color = Color(1.0, 1.0, 1.0, 0.95)
		_overshoot_overlay.color.a = 0.0
		_accuracy_label.visible = false
		_bar_panel.position = _base_bar_pos
		_indicator.position = Vector2(_base_bar_pos.x, _base_indicator_y - INDICATOR_HEIGHT * 0.5)


func _process(delta: float) -> void:
	if not _is_overshooting or not visible:
		return

	_overshoot_time += delta
	# Intensity ramps up with overshoot amount (0→1)
	var intensity: float = clampf(_overshoot_amount * 3.0, 0.0, 1.0)

	# --- Red glow overlay: pulse faster and brighter with more overshoot ---
	var pulse_speed: float = 6.0 + intensity * 8.0
	var base_alpha: float = 0.1 + intensity * 0.25
	var pulse_alpha: float = base_alpha + 0.1 * sin(_overshoot_time * pulse_speed)
	_overshoot_overlay.color = Color(1.0, 0.1, 0.1, pulse_alpha)

	# --- Indicator: rise above bar top + shake ---
	var rise: float = clampf(_overshoot_amount * 2.0, 0.0, 1.0) * OVERSHOOT_MAX_RISE
	var indicator_y: float = _base_bar_pos.y + 4.0 - rise
	var shake_x: float = randf_range(-SHAKE_INTENSITY, SHAKE_INTENSITY) * intensity
	_indicator.position = Vector2(
		_base_bar_pos.x + shake_x,
		indicator_y - INDICATOR_HEIGHT * 0.5,
	)

	# Pulse indicator color
	var ind_alpha: float = 0.7 + 0.3 * sin(_overshoot_time * pulse_speed)
	_indicator.color = Color(1.0, 0.3, 0.2, ind_alpha)

	# --- Bar wobble: horizontal oscillation ---
	var wobble_x: float = sin(_overshoot_time * 12.0) * WOBBLE_INTENSITY * intensity
	_bar_panel.position = Vector2(_base_bar_pos.x + wobble_x, _base_bar_pos.y)


## Set the terrain zone bands. Call when aim direction or angle changes.
## bands: Array of {percent: float (0-1), color: Color, zone_type: int}
func set_bands(bands: Array[Dictionary]) -> void:
	_bands = bands
	_zone_drawer.queue_redraw()


func _draw_zones() -> void:
	var w: float = _zone_drawer.size.x
	var h: float = _zone_drawer.size.y

	if _bands.size() < 2:
		# No data — draw solid dark
		_zone_drawer.draw_rect(Rect2(0, 0, w, h), Color(0.1, 0.1, 0.1, 0.5))
		return

	# Draw bands from bottom (0%) to top (100%)
	for i: int in range(_bands.size() - 1):
		var b0: Dictionary = _bands[i]
		var b1: Dictionary = _bands[i + 1]
		var y_bottom: float = h * (1.0 - b0["percent"])
		var y_top: float = h * (1.0 - b1["percent"])
		var rect_h: float = y_bottom - y_top
		if rect_h < 0.5:
			continue
		var col: Color = b0["color"]
		col.a = 0.7
		_zone_drawer.draw_rect(Rect2(0, y_top, w, rect_h), col)

		# Zone type abbreviation centered in the band
		var band_h: float = absf(rect_h)
		if band_h > 14.0:
			var zone_type: int = b0.get("zone_type", -1)
			var label_text: String = ZONE_LABELS.get(zone_type, "")
			if label_text != "":
				var font: Font = ThemeDB.fallback_font
				var font_size: int = 14
				var text_size: Vector2 = font.get_string_size(
					label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size
				)
				var tx: float = (w - text_size.x) * 0.5
				var ty: float = y_top + (band_h + text_size.y) * 0.5
				_zone_drawer.draw_string(
					font, Vector2(tx, ty), label_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
					Color(1.0, 1.0, 1.0, 0.6),
				)
