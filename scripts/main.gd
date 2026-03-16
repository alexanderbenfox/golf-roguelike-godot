## Main — scene coordinator.
##
## Wires managers together and owns the Godot scene tree interactions
## (spawning Hole nodes, resetting ball, showing UI).
extends Node3D

const GameStateScript = preload("res://state/game_state.gd")
const PlayerStateScript = preload("res://state/player_state.gd")
const ProceduralHoleScript = preload("res://scripts/procedural_hole.gd")
const UpgradeScreenScript = preload("res://scripts/ui/upgrade_screen.gd")

@onready var scoring_manager: ScoringManager = $ScoringManager
@onready var score_ui: Control = $UICanvas/ScoreUI
@onready var hole_complete_ui: HoleCompleteUI = $UICanvas/HoleCompleteUI
@onready var course_manager: CourseManager = $CourseManager
@onready var network_manager: NetworkManager = $NetworkManager
@onready var turn_manager: TurnManager = $TurnManager
@onready var ball: RigidBody3D = $GolfBall/RigidBody3D
@onready var camera: Camera3D = $Camera3D

var game_state: GameStateScript
var current_hole: ProceduralHole
var _upgrade_screen: UpgradeScreen


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
	ball.out_of_bounds.connect(_on_ball_out_of_bounds)

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
	var player: PlayerState = PlayerStateScript.new()
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

func _on_game_started(_state: GameState) -> void:
	game_state = _state
	ball.peer_id = network_manager.get_my_peer_id()
	ball.is_local_player = true
	course_manager.start_course()


# -------------------------------------------------------------------------
# Course / hole callbacks
# -------------------------------------------------------------------------

func _on_hole_started(_hole_number: int, _par: int) -> void:
	if current_hole:
		current_hole.queue_free()

	var layout: HoleGenerator.HoleLayout = course_manager.get_current_layout()

	current_hole = ProceduralHoleScript.new()
	add_child(current_hole)
	current_hole.build(layout)
	current_hole.ball_entered_cup.connect(_on_ball_entered_cup)

	var tee_position: Vector3 = current_hole.get_tee_world_position()
	ball.reset_position(tee_position)
	ball.set_bounds_check(current_hole.is_out_of_bounds)
	var my_player: PlayerState = \
		game_state.players.get(network_manager.get_my_peer_id()) as PlayerState
	ball.setup_physics_params(my_player)

	turn_manager.start_hole(tee_position)


func _on_ball_entered_cup() -> void:
	var my_id: int = network_manager.get_my_peer_id()
	scoring_manager.complete_hole()
	turn_manager.notify_player_holed_out(my_id)


func _on_ball_at_rest(peer_id: int) -> void:
	turn_manager.notify_ball_at_rest(peer_id)


func _on_ball_out_of_bounds(_peer_id: int) -> void:
	# Ball has already been teleported back to last_shot_position by golf_ball.gd.
	# The turn stays active — the player re-aims and shoots from there.
	_show_oob_message()


func _show_oob_message() -> void:
	var label := Label.new()
	label.text = "Out of Bounds!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.offset_top = 80.0
	$UICanvas.add_child(label)
	# Remove after 2 seconds
	get_tree().create_timer(2.0).timeout.connect(label.queue_free)


func _on_turn_manager_hole_complete() -> void:
	pass  # Scoring handled via _on_ball_entered_cup → scoring_manager.complete_hole()


func _on_hole_completed(strokes: int, par: int, score_name: String) -> void:
	camera.input_enabled = false
	ball.set_turn_active(false)
	hole_complete_ui.show_result(strokes, par, score_name)


func _on_next_hole_requested() -> void:
	# Last hole already handled by _on_course_completed — don't show upgrade screen
	if course_manager.current_hole_index >= course_manager.holes_in_course:
		return
	_show_upgrade_screen()


func _show_upgrade_screen() -> void:
	_upgrade_screen = UpgradeScreenScript.new()
	add_child(_upgrade_screen)
	var choices := UpgradeRegistry.roll_choices(MetaProgression.meta_level)
	_upgrade_screen.present(choices)
	_upgrade_screen.upgrade_selected.connect(_on_upgrade_selected)


func _on_upgrade_selected(upgrade: UpgradeDefinition) -> void:
	_upgrade_screen = null  # already queue_free'd itself
	camera.input_enabled = true
	if upgrade != null:
		var my_id: int = network_manager.get_my_peer_id()
		var player: PlayerState = game_state.players.get(my_id) as PlayerState
		if player:
			upgrade.apply(player)
			ball.setup_physics_params(player)
	MetaProgression.on_hole_complete()
	course_manager.advance_to_next_hole()


func _on_course_completed(total_strokes: int, total_par: int) -> void:
	print("Course complete! Strokes: %d  Par: %d" % [total_strokes, total_par])
	MetaProgression.on_run_complete()


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
