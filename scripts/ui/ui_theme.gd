## UITheme — centralized color palette for all UI elements.
##
## Palette: earthy golf-course aesthetic.
##   BARK · FOREST · OLIVE · FERN · GRASS · SAND · PARCHMENT · SKY · POND · CLAY
##
## Usage: UITheme.PANEL_BG, UITheme.GRASS, etc.
class_name UITheme

## ── Raw palette ──────────────────────────────────────────────────────────────
const BARK      := Color(0.184, 0.106, 0.067)  ## #2f1b11 — very dark brown
const FOREST    := Color(0.157, 0.212, 0.094)  ## #283618 — dark forest green
const OLIVE     := Color(0.376, 0.424, 0.220)  ## #606c38 — medium olive green
const FERN      := Color(0.522, 0.584, 0.239)  ## #85953d — olive-yellow green
const GRASS     := Color(0.333, 0.510, 0.153)  ## #558227 — bright medium green
const SAND      := Color(0.553, 0.522, 0.337)  ## #8d8556 — tan / khaki
const PARCHMENT := Color(0.941, 0.918, 0.847)  ## #f0ead8 — light cream
const SKY       := Color(0.659, 0.733, 0.800)  ## #a8bbcc — light steel blue
const POND      := Color(0.043, 0.224, 0.282)  ## #0b3948 — dark teal / navy
const CLAY      := Color(0.412, 0.173, 0.173)  ## #692c2c — dark red / maroon

## ── Panel backgrounds (with alpha) ───────────────────────────────────────────
const PANEL_BG    := Color(0.184, 0.106, 0.067, 0.88)  ## BARK  — primary panels
const CARD_BG     := Color(0.157, 0.212, 0.094, 0.92)  ## FOREST — upgrade cards
const OVERLAY_DIM := Color(0.184, 0.106, 0.067, 0.80)  ## BARK  — fullscreen dim
const HUD_BG      := Color(0.184, 0.106, 0.067, 0.75)  ## BARK  — small HUD panels

## ── Text ─────────────────────────────────────────────────────────────────────
const TEXT_PRIMARY   := Color(0.941, 0.918, 0.847)        ## PARCHMENT — main text
const TEXT_SECONDARY := Color(0.553, 0.522, 0.337)        ## SAND — labels / captions
const TEXT_HINT      := Color(0.659, 0.733, 0.800, 0.70)  ## SKY  — key hints

## ── Scoring ──────────────────────────────────────────────────────────────────
const SCORE_GOOD    := Color(0.333, 0.510, 0.153)  ## GRASS — under par
const SCORE_NEUTRAL := Color(0.553, 0.522, 0.337)  ## SAND  — even par
const SCORE_BAD     := Color(0.412, 0.173, 0.173)  ## CLAY  — over par

## ── Upgrade rarities ─────────────────────────────────────────────────────────
const RARITY_COMMON   := Color(0.553, 0.522, 0.337)  ## SAND
const RARITY_UNCOMMON := Color(0.333, 0.510, 0.153)  ## GRASS
const RARITY_RARE     := Color(0.659, 0.733, 0.800)  ## SKY

## ── Borders ──────────────────────────────────────────────────────────────────
const BORDER_NORMAL := Color(0.376, 0.424, 0.220)  ## OLIVE
const BORDER_ACCENT := Color(0.553, 0.522, 0.337)  ## SAND

## ── Button styles ────────────────────────────────────────────────────────────
static func make_button_normal() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.376, 0.424, 0.220)  # OLIVE
	s.set_corner_radius_all(5)
	s.content_margin_left   = 16
	s.content_margin_right  = 16
	s.content_margin_top    = 8
	s.content_margin_bottom = 8
	return s

static func make_button_hover() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.333, 0.510, 0.153)  # GRASS
	s.set_corner_radius_all(5)
	s.content_margin_left   = 16
	s.content_margin_right  = 16
	s.content_margin_top    = 8
	s.content_margin_bottom = 8
	return s

static func make_button_pressed() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.157, 0.212, 0.094)  # FOREST
	s.set_corner_radius_all(5)
	s.content_margin_left   = 16
	s.content_margin_right  = 16
	s.content_margin_top    = 8
	s.content_margin_bottom = 8
	return s

static func apply_button_theme(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal",  make_button_normal())
	btn.add_theme_stylebox_override("hover",   make_button_hover())
	btn.add_theme_stylebox_override("pressed", make_button_pressed())
	btn.add_theme_stylebox_override("focus",   make_button_normal())
	btn.add_theme_color_override("font_color",         Color(0.941, 0.918, 0.847))
	btn.add_theme_color_override("font_hover_color",   Color(0.941, 0.918, 0.847))
	btn.add_theme_color_override("font_pressed_color", Color(0.941, 0.918, 0.847))
