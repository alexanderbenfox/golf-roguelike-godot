class_name MainMenu
extends Control

const GAME_SCENE := "res://node_3d.tscn"

@onready var play_button: Button = $VBoxContainer/PlayButton


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	play_button.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
