## DebugOverlay — semi-transparent panel showing runtime debug info.
##
## Add entries with `set_value(key, value)` from anywhere.
## Call `remove_value(key)` to stop showing a line.
## Toggled with F3.
class_name DebugOverlay
extends PanelContainer

var _label: Label
var _entries: Dictionary = {}  # key -> String


func _ready() -> void:
	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.8))
	add_child(_label)

	# Top-left
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 10.0
	offset_top = 10.0

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F3:
			visible = not visible
			get_viewport().set_input_as_handled()


func set_value(key: String, value: Variant) -> void:
	_entries[key] = str(value)
	_refresh()


func remove_value(key: String) -> void:
	_entries.erase(key)
	_refresh()


func _refresh() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for key: String in _entries:
		lines.append("%s: %s" % [key, _entries[key]])
	_label.text = "\n".join(lines)
