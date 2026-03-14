## TurnManager — server-authoritative turn sequencing.
##
## Responsibility:
##   - Know whose turn it is.
##   - Validate that shots come from the correct player.
##   - Advance the turn when a ball comes to rest.
##   - Detect when all players have holed out and emit hole_complete.
##
## Only the SERVER calls advance_turn() and emits server-side signals.
## Clients learn about turn changes through NetworkManager.turn_advanced.
class_name TurnManager
extends Node

signal turn_started(peer_id: int)
signal hole_complete()

var game_state: GameState
var network_manager: NetworkManager


func setup(state: GameState, net_mgr: NetworkManager) -> void:
	game_state = state
	network_manager = net_mgr
	network_manager.shot_received.connect(_on_shot_received)
	network_manager.turn_advanced.connect(_on_turn_advanced)


# -------------------------------------------------------------------------
# Server-side: called by game logic to begin a hole
# -------------------------------------------------------------------------

func start_hole(tee_position: Vector3) -> void:
	# Reset all players for this hole
	for player: PlayerState in game_state.players.values():
		player.reset_for_hole(tee_position)

	_sort_turn_order()
	game_state.current_turn_index = 0

	var current_id := game_state.get_current_player_id()
	if multiplayer.is_server():
		network_manager.server_advance_turn(current_id)


# Sort by total strokes ascending so the player furthest behind shoots first
# (matches real stroke-play convention).
func _sort_turn_order() -> void:
	var ids: Array = game_state.players.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		return game_state.players[a].total_strokes < game_state.players[b].total_strokes
	)
	game_state.turn_order.assign(ids)


# -------------------------------------------------------------------------
# Validation — only the server runs this
# -------------------------------------------------------------------------

## Returns true if peer_id is allowed to shoot right now.
func is_valid_shooter(peer_id: int) -> bool:
	if game_state.phase != GameState.Phase.AIMING:
		return false
	return peer_id == game_state.get_current_player_id()


# -------------------------------------------------------------------------
# Shot tracking
# -------------------------------------------------------------------------

func _on_shot_received(peer_id: int, _direction: Vector3, _power: float) -> void:
	# Update state: this player is now simulating
	if game_state.players.has(peer_id):
		game_state.phase = GameState.Phase.SIMULATING


## Called by the ball controller when a specific player's ball comes to rest.
func notify_ball_at_rest(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player: PlayerState = game_state.players.get(peer_id)
	if player == null:
		return

	if player.is_hole_complete:
		_check_hole_complete()
		return

	# Not in cup yet — advance to next player
	game_state.phase = GameState.Phase.AIMING
	_advance_turn()


## Called by the ball/cup logic when a player's ball enters the cup.
func notify_player_holed_out(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player: PlayerState = game_state.players.get(peer_id)
	if player == null:
		return

	player.is_hole_complete = true
	_check_hole_complete()


# -------------------------------------------------------------------------
# Turn advancement — server only
# -------------------------------------------------------------------------

func _advance_turn() -> void:
	if game_state.all_players_hole_complete():
		hole_complete.emit()
		return

	game_state.advance_turn()
	var next_id := game_state.get_current_player_id()
	network_manager.server_advance_turn(next_id)


func _check_hole_complete() -> void:
	if game_state.all_players_hole_complete():
		hole_complete.emit()
	else:
		_advance_turn()


# -------------------------------------------------------------------------
# Client-side: react to turn changes broadcast from server
# -------------------------------------------------------------------------

func _on_turn_advanced(current_player_id: int) -> void:
	game_state.phase = GameState.Phase.AIMING
	turn_started.emit(current_player_id)


func is_my_turn() -> bool:
	return game_state.get_current_player_id() == network_manager.get_my_peer_id()
