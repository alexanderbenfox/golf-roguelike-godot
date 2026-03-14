## Main — scene coordinator.
##
## Wires managers together and owns the Godot scene tree interactions
## (spawning Hole nodes, resetting ball, showing UI).
extends Node3D

const GameStateScript = preload("res://state/game_state.gd")
const PlayerStateScript = preload("res://state/player_state.gd")

@onready var scoring_manager: ScoringManager = $ScoringManager
@onready var score_ui = $UICanvas/ScoreUI
@onready var hole_complete_ui = $UICanvas/HoleCompleteUI
@onready var course_manager: CourseManager = $CourseManager
@onready var network_manager = $NetworkManager
@onready var turn_manager = $TurnManager
@onready var ball: RigidBody3D = $GolfBall/RigidBody3D

var game_state: GameStateScript
var current_hole: Hole


func _ready() -> void:
	# Wire UI → ScoringManager
	score_ui.setup(scoring_manager)
	course_manager.setup(scoring_manager)

	# Wire course/scoring signals
	course_manager.hole_started.connect(_on_hole_started)
	course_manager.course_completed.connect(_on_course_completed)
	scoring_manager.hole_completed.connect(_on_hole_completed)
	hole_complete_ui.next_hole_requested.connect(_on_next_hole_requested)

	# Wire ball signals → network
	ball.shot_ready.connect(_on_shot_ready)
	ball.ball_at_rest.connect(_on_ball_at_rest)

	# Wire network → ball and turn manager
	network_manager.shot_received.connect(_on_shot_received)
	network_manager.game_started.connect(_on_game_started)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.hole_complete.connect(_on_turn_manager_hole_complete)

	# Start single-player session
	_start_singleplayer()


func _start_singleplayer() -> void:
	network_manager.setup_singleplayer("Player 1")

	game_state = GameStateScript.new()
	game_state.course_seed = randi()

	var local_id: int = network_manager.get_my_peer_id()
	var player = PlayerStateScript.new()
	player.peer_id = local_id
	player.display_name = "Player 1"
	game_state.players[local_id] = player
	game_state.turn_order = [local_id]

	turn_manager.setup(game_state, network_manager)
	course_manager.generate_course(game_state.course_seed)
	network_manager.server_start_game(game_state)


# -------------------------------------------------------------------------
# Network callbacks
# -------------------------------------------------------------------------

func _on_game_started(_state) -> void:
	game_state = _state
	ball.peer_id = network_manager.get_my_peer_id()
	ball.is_local_player = true
	course_manager.start_course()


# -------------------------------------------------------------------------
# Course / hole callbacks
# -------------------------------------------------------------------------

func _on_hole_started(hole_number: int, par: int) -> void:
	if current_hole:
		current_hole.queue_free()

	current_hole = Hole.new()
	current_hole.par = par
	current_hole.hole_number = hole_number
	add_child(current_hole)

	var cup_position := Vector3(0, 0.4, -20)
	current_hole.set_cup_position(cup_position)
	current_hole.ball_entered_cup.connect(_on_ball_entered_cup)

	var tee_position := Vector3(0, 1, 0)
	ball.reset_position(tee_position)
	ball.setup_physics_params(game_state.players.get(network_manager.get_my_peer_id()))

	turn_manager.start_hole(tee_position)


func _on_ball_entered_cup() -> void:
	var my_id: int = network_manager.get_my_peer_id()
	scoring_manager.complete_hole()
	turn_manager.notify_player_holed_out(my_id)


func _on_ball_at_rest(peer_id: int) -> void:
	turn_manager.notify_ball_at_rest(peer_id)


func _on_turn_manager_hole_complete() -> void:
	pass  # Scoring handled via _on_ball_entered_cup → scoring_manager.complete_hole()


func _on_hole_completed(strokes: int, par: int, score_name: String) -> void:
	hole_complete_ui.show_result(strokes, par, score_name)


func _on_next_hole_requested() -> void:
	pass  # CourseManager advances automatically via its own signal chain


func _on_course_completed(total_strokes: int, total_par: int) -> void:
	print("Course complete! Strokes: %d  Par: %d" % [total_strokes, total_par])


# -------------------------------------------------------------------------
# Turn callbacks
# -------------------------------------------------------------------------

func _on_turn_started(peer_id: int) -> void:
	var my_id: int = network_manager.get_my_peer_id()
	ball.set_turn_active(peer_id == my_id)


# -------------------------------------------------------------------------
# Shot routing — local → network → all balls
# -------------------------------------------------------------------------

func _on_shot_ready(direction: Vector3, power: float) -> void:
	scoring_manager.add_stroke()
	network_manager.submit_shot(direction, power)


func _on_shot_received(_peer_id: int, direction: Vector3, power: float) -> void:
	# Single-player: only one ball. Multiplayer: route by _peer_id to that player's ball node.
	ball.play_shot(direction, power)
