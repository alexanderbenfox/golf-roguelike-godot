## NetworkManager — single source of truth for multiplayer connectivity and RPCs.
##
## Authority model:
##   - Server (peer_id == 1) owns GameState and validates all game actions.
##   - Clients send requests; server validates then broadcasts results.
##   - In single-player / offline mode the "server" is the local process (peer_id 1).
##
## Shot flow:
##   LocalPlayer aims → submit_shot() → [RPC to server] → server validates turn
##   → rpc_broadcast_shot() to all → shot_received signal → each client simulates.
class_name NetworkManager
extends Node

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

# Emitted on all peers when a player connects and their name is known
signal player_connected(peer_id: int, player_name: String)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal connection_failed()

# Emitted on all peers when the server broadcasts a validated shot
signal shot_received(peer_id: int, direction: Vector3, power: float)

# Emitted on all peers when the server starts/syncs the game
signal game_started(state: GameState)

# Emitted on all peers when the server advances the turn
signal turn_advanced(current_player_id: int)

# peer_id → display name, populated on all peers
var player_names: Dictionary = {}


# -------------------------------------------------------------------------
# Connection helpers
# -------------------------------------------------------------------------

func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	player_names[1] = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func join_game(player_name: String, address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server.bind(player_name))
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


## Set up as a single-player session (no real network peer needed).
## Assigns peer_id 1 so the rest of the code treats this as the server.
func setup_singleplayer(player_name: String) -> void:
	player_names[1] = player_name
	# No ENet peer — multiplayer.get_unique_id() returns 1 by default in offline mode


func is_server() -> bool:
	return multiplayer.is_server()


func get_my_peer_id() -> int:
	return multiplayer.get_unique_id()


# -------------------------------------------------------------------------
# Internal connection callbacks
# -------------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	# Ask the new peer to send us their name
	_request_player_info.rpc_id(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	player_names.erase(peer_id)
	player_disconnected.emit(peer_id)


func _on_connected_to_server(player_name: String) -> void:
	var my_id := multiplayer.get_unique_id()
	player_names[my_id] = player_name
	_register_player.rpc_id(1, player_name)


func _on_connection_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	server_disconnected.emit()


# -------------------------------------------------------------------------
# Player registration RPCs (internal — prefixed with _)
# -------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _request_player_info() -> void:
	# Called on the client by the server; client responds with their name
	var my_id := multiplayer.get_unique_id()
	_register_player.rpc_id(1, player_names.get(my_id, "Player"))


@rpc("any_peer", "call_remote", "reliable")
func _register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	player_names[sender_id] = player_name
	_sync_player_list.rpc(player_names)
	player_connected.emit(sender_id, player_name)


@rpc("authority", "call_local", "reliable")
func _sync_player_list(names: Dictionary) -> void:
	player_names = names


# -------------------------------------------------------------------------
# Game flow — called by server-side game logic
# -------------------------------------------------------------------------

## Server calls this to start the game for all peers.
func server_start_game(state: GameState) -> void:
	assert(multiplayer.is_server(), "Only the server may start the game")
	_rpc_start_game.rpc(state.to_dict())


@rpc("authority", "call_local", "reliable")
func _rpc_start_game(serialized: Dictionary) -> void:
	game_started.emit(GameState.from_dict(serialized))


## Server calls this to tell all peers whose turn it is.
func server_advance_turn(current_player_id: int) -> void:
	assert(multiplayer.is_server(), "Only the server may advance turns")
	_rpc_advance_turn.rpc(current_player_id)


@rpc("authority", "call_local", "reliable")
func _rpc_advance_turn(current_player_id: int) -> void:
	turn_advanced.emit(current_player_id)


# -------------------------------------------------------------------------
# Shot submission — the core networked action
# -------------------------------------------------------------------------

## Called by the LOCAL player to submit their shot.
## Routes through server in multiplayer; fires directly in single-player.
func submit_shot(direction: Vector3, power: float) -> void:
	if multiplayer.is_server():
		# Server player: validate immediately and broadcast
		_broadcast_shot(multiplayer.get_unique_id(), direction, power)
	else:
		_rpc_submit_shot.rpc_id(1, direction, power)


## Client → Server: request to fire a shot.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_shot(direction: Vector3, power: float) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	# TurnManager will validate it's actually this player's turn via signal.
	# For now trust the sender; add validation in TurnManager._on_shot_submitted.
	_broadcast_shot(sender_id, direction, power)


## Server → All: a validated shot is happening.
func _broadcast_shot(peer_id: int, direction: Vector3, power: float) -> void:
	_rpc_broadcast_shot.rpc(peer_id, direction, power)


@rpc("authority", "call_local", "reliable")
func _rpc_broadcast_shot(peer_id: int, direction: Vector3, power: float) -> void:
	shot_received.emit(peer_id, direction, power)
