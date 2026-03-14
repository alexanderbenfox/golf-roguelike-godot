## LobbyUI — host/join screen shown before a game begins.
##
## Singleplayer: "Play" button skips directly to the game scene.
## Multiplayer:  "Host" starts a server; "Join" connects to an address.
class_name LobbyUI
extends Control

signal play_singleplayer()
signal host_requested(player_name: String)
signal join_requested(player_name: String, address: String)

@onready var name_input: LineEdit = %NameInput
@onready var address_input: LineEdit = %AddressInput
@onready var status_label: Label = %StatusLabel
@onready var join_section: Control = %JoinSection
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var play_button: Button = %PlayButton


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	set_status("")


func set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func show_connecting() -> void:
	set_status("Connecting...")
	host_button.disabled = true
	join_button.disabled = true


func show_error(msg: String) -> void:
	set_status("Error: " + msg)
	host_button.disabled = false
	join_button.disabled = false


func _on_play_pressed() -> void:
	play_singleplayer.emit()


func _on_host_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	show_connecting()
	host_requested.emit(player_name)


func _on_join_pressed() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	show_connecting()
	join_requested.emit(player_name, address)
