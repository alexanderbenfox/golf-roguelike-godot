## Lobby — root script for the lobby scene.
## Owns the NetworkManager so it persists into the game scene via change_scene_to_file.
## Passes connection info to the game via a global or scene-tree autoload (future work).
## For now, singleplayer just transitions directly; multiplayer waits for players to be ready.
extends Node

const GAME_SCENE := "res://main.tscn"
const NetworkManagerScript = preload("res://scripts/managers/network_manager.gd")

@onready var lobby_ui: LobbyUI = $LobbyUI
@onready var network_manager: Node = $NetworkManager

# Shared across the transition to game scene via GameSession autoload (see below).
# Until autoload is set up, singleplayer passes nothing — game scene self-initializes.


func _ready() -> void:
	lobby_ui.play_singleplayer.connect(_on_play_singleplayer)
	lobby_ui.host_requested.connect(_on_host_requested)
	lobby_ui.join_requested.connect(_on_join_requested)
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.connection_failed.connect(_on_connection_failed)
	network_manager.server_disconnected.connect(_on_server_disconnected)


func _on_play_singleplayer() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_host_requested(player_name: String) -> void:
	var err := network_manager.host_game(player_name)
	if err != OK:
		lobby_ui.show_error("Failed to host (error %d)" % err)
		return
	lobby_ui.set_status("Hosting on port %d — waiting for players…" % NetworkManager.DEFAULT_PORT)
	# Host can start the game immediately or wait; for now start after a moment.
	# In a real game you'd have a "Start Game" button visible only to the host.
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_join_requested(player_name: String, address: String) -> void:
	var err := network_manager.join_game(player_name, address)
	if err != OK:
		lobby_ui.show_error("Failed to connect (error %d)" % err)
		return


func _on_player_connected(peer_id: int, player_name: String) -> void:
	lobby_ui.set_status("Player connected: %s" % player_name)


func _on_connection_failed() -> void:
	lobby_ui.show_error("Could not connect to server.")


func _on_server_disconnected() -> void:
	lobby_ui.show_error("Server disconnected.")
