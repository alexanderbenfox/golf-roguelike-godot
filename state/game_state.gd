class_name GameState
extends RefCounted

enum Phase {
	LOBBY,
	HOLE_INTRO,
	AIMING,
	SIMULATING,
	HOLE_COMPLETE,
	ROGUELIKE_PICK,
	COURSE_COMPLETE,
}

var course_seed: int = 0
var current_hole: int = 0        # 0-indexed internally
var holes_in_course: int = 9
var hole_pars: Array[int] = []
var phase: Phase = Phase.LOBBY

# Turn order: list of peer_ids in shot order
var turn_order: Array[int] = []
var current_turn_index: int = 0

# players[peer_id] = PlayerState
var players: Dictionary = {}


func get_current_player_id() -> int:
	if turn_order.is_empty():
		return -1
	return turn_order[current_turn_index % turn_order.size()]


func get_current_player() -> PlayerState:
	return players.get(get_current_player_id(), null) as PlayerState


func all_players_hole_complete() -> bool:
	for player: PlayerState in players.values():
		if not player.is_hole_complete:
			return false
	return true


func advance_turn() -> void:
	# Skip players who already holed out
	for i in range(turn_order.size()):
		current_turn_index = (current_turn_index + 1) % turn_order.size()
		var pid: int = turn_order[current_turn_index]
		if players.has(pid) and not players[pid].is_hole_complete:
			return
	# All players are done — caller should handle hole_complete


func get_hole_display_number() -> int:
	return current_hole + 1


func get_current_par() -> int:
	if current_hole < hole_pars.size():
		return hole_pars[current_hole]
	return 3


func to_dict() -> Dictionary:
	var serialized_players: Dictionary = {}
	for pid: int in players:
		serialized_players[str(pid)] = players[pid].to_dict()
	return {
		"course_seed": course_seed,
		"current_hole": current_hole,
		"holes_in_course": holes_in_course,
		"hole_pars": hole_pars,
		"phase": phase,
		"turn_order": turn_order,
		"current_turn_index": current_turn_index,
		"players": serialized_players,
	}


static func from_dict(d: Dictionary) -> GameState:
	var gs := GameState.new()
	gs.course_seed = d["course_seed"]
	gs.current_hole = d["current_hole"]
	gs.holes_in_course = d["holes_in_course"]
	gs.hole_pars.assign(d["hole_pars"])
	gs.phase = d["phase"]
	gs.turn_order.assign(d["turn_order"])
	gs.current_turn_index = d["current_turn_index"]
	for pid_str: String in d["players"]:
		var ps := PlayerState.from_dict(d["players"][pid_str])
		gs.players[int(pid_str)] = ps
	return gs
