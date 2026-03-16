## UpgradeScreen — full-screen upgrade selection shown between holes.
##
## Built entirely in code; no .tscn needed.
## Usage:
##   var screen = UpgradeScreen.new()
##   add_child(screen)
##   screen.present(choices)          # Array of UpgradeDefinition
##   screen.upgrade_selected.connect(my_handler)
##
## The node frees itself after the player picks an upgrade.
class_name UpgradeScreen
extends CanvasLayer

signal upgrade_selected(upgrade: UpgradeDefinition)

const CARD_SIZE     := Vector2(260, 360)
const CARD_BG       := Color(0.10, 0.10, 0.14)
const OVERLAY_COLOR := Color(0.0, 0.0, 0.0, 0.80)

const RARITY_COLORS: Dictionary = {
	0: Color(0.75, 0.75, 0.75),   # COMMON    — silver
	1: Color(0.20, 0.85, 0.35),   # UNCOMMON  — green
	2: Color(0.40, 0.60, 1.00),   # RARE      — blue
}
const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare"]


## Show the upgrade selection UI with the given choices.
func present(choices: Array) -> void:
	_build_ui(choices)


# -------------------------------------------------------------------------
# UI construction
# -------------------------------------------------------------------------

func _build_ui(choices: Array) -> void:
	# Full-screen backdrop
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Semi-transparent dim
	var overlay := ColorRect.new()
	overlay.color = OVERLAY_COLOR
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	# Centre everything
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Choose an Upgrade"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	# Subtitle showing current meta level
	var meta_label := Label.new()
	var lvl: int = MetaProgression.meta_level
	meta_label.text = "Meta Level %d" % lvl
	meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_label.add_theme_font_size_override("font_size", 14)
	meta_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(meta_label)

	# Cards row
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vbox.add_child(row)

	if choices.is_empty():
		var empty := Label.new()
		empty.text = "No upgrades available."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(empty)
	else:
		for upgrade in choices:
			row.add_child(_make_card(upgrade as UpgradeDefinition))

	# Skip button (take no upgrade)
	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.pressed.connect(_on_skip_pressed)
	skip_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(skip_btn)


func _make_card(upgrade: UpgradeDefinition) -> Button:
	var rarity_color: Color = RARITY_COLORS.get(upgrade.rarity, Color.WHITE)

	# Card is a Button so the entire surface is clickable
	var btn := Button.new()
	btn.custom_minimum_size = CARD_SIZE
	btn.flat = true
	btn.pressed.connect(func(): _on_card_pressed(upgrade))

	# Normal style
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = CARD_BG
	normal_style.border_color = rarity_color
	normal_style.set_border_width_all(3)
	normal_style.set_corner_radius_all(8)
	normal_style.content_margin_left   = 18
	normal_style.content_margin_right  = 18
	normal_style.content_margin_top    = 18
	normal_style.content_margin_bottom = 18

	# Hover style — slightly lighter background, brighter border
	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color     = Color(0.17, 0.17, 0.22)
	hover_style.border_color = rarity_color.lightened(0.25)

	btn.add_theme_stylebox_override("normal",  normal_style)
	btn.add_theme_stylebox_override("hover",   hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)
	btn.add_theme_stylebox_override("focus",   normal_style)

	# Content VBox (mouse_filter = IGNORE so clicks reach the Button parent)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	btn.add_child(vbox)

	# Rarity tag
	var rarity_label := Label.new()
	rarity_label.text = RARITY_NAMES[upgrade.rarity]
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_size_override("font_size", 13)
	rarity_label.add_theme_color_override("font_color", rarity_color)
	vbox.add_child(rarity_label)

	# Upgrade name
	var name_label := Label.new()
	name_label.text = upgrade.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)

	# Divider
	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# Description
	var desc_label := Label.new()
	desc_label.text = upgrade.description
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc_label)

	# Effect summary (green tint)
	var summary := upgrade.get_effects_summary()
	if not summary.is_empty():
		var effects_label := Label.new()
		effects_label.text = summary
		effects_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		effects_label.add_theme_font_size_override("font_size", 14)
		effects_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.65))
		vbox.add_child(effects_label)

	return btn


# -------------------------------------------------------------------------
# Interaction
# -------------------------------------------------------------------------

func _on_card_pressed(upgrade: UpgradeDefinition) -> void:
	upgrade_selected.emit(upgrade)
	queue_free()


func _on_skip_pressed() -> void:
	upgrade_selected.emit(null)
	queue_free()
