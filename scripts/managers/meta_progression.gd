## MetaProgression — persistent cross-run progression tracker.
##
## Saved to user://meta_progression.cfg so it survives between game sessions.
## Registered as an Autoload named "MetaProgression" in Project Settings.
##
## meta_level gates which upgrades are available:
##   Level 0 — default (0 runs completed)
##   Level 1 — after 2  runs
##   Level 2 — after 5  runs
##   Level 3 — after 10 runs
extends Node

const SAVE_PATH := "user://meta_progression.cfg"

var meta_level: int = 0
var runs_completed: int = 0
var total_holes_completed: int = 0


func _ready() -> void:
	_load()


## Call when the player finishes a complete course run.
func on_run_complete() -> void:
	runs_completed += 1
	_recalculate_meta_level()
	_save()


## Call when the player completes any individual hole.
func on_hole_complete() -> void:
	total_holes_completed += 1
	_save()


## Wipe all saved progress (useful for a "reset meta" option in settings).
func reset() -> void:
	meta_level = 0
	runs_completed = 0
	total_holes_completed = 0
	_save()


func _recalculate_meta_level() -> void:
	if runs_completed >= 10:
		meta_level = 3
	elif runs_completed >= 5:
		meta_level = 2
	elif runs_completed >= 2:
		meta_level = 1
	else:
		meta_level = 0


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "meta_level", meta_level)
	cfg.set_value("progress", "runs_completed", runs_completed)
	cfg.set_value("progress", "total_holes_completed", total_holes_completed)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	meta_level = cfg.get_value("progress", "meta_level", 0)
	runs_completed = cfg.get_value("progress", "runs_completed", 0)
	total_holes_completed = cfg.get_value("progress", "total_holes_completed", 0)
