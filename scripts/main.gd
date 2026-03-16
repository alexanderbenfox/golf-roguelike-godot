## Main — scene coordinator.
##
## Wires managers together and owns the Godot scene tree interactions
## (spawning Hole nodes, resetting ball, showing UI).
extends Node3D

const GameStateScript = preload("res://state/game_state.gd")
const PlayerStateScript = preload("res://state/player_state.gd")
const ProceduralHoleScript = preload("res://scripts/procedural_hole.gd")
const UpgradeScreenScript = preload("res://scripts/ui/upgrade_screen.gd")
const GolferStatsScript = preload("res://resources/golfer_stats.gd")
const ScorecardUIScript = preload("res://scripts/ui/scorecard_ui.gd")

## Starting stats for the golfer — edit in Inspector to tune defaults.
@export var golfer_stats: Resource  # GolferStats

## Available upgrades — drag UpgradeDefinition .tres files here in the Inspector.
## Toggle each definition's `enabled` flag to include/exclude it from rolls.
@export var upgrade_pool: Array[UpgradeDefinition] = []

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
var _distance_label: Label
var _scorecard: Control


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

	# Set up sky and lighting
	_setup_environment()

	# Provide the editor-configured upgrade pool to the registry
	UpgradeRegistry.set_pool(upgrade_pool)

	# Scorecard
	_scorecard = ScorecardUIScript.new()
	$UICanvas.add_child(_scorecard)

	# Start single-player session
	_start_singleplayer()


func _setup_environment() -> void:
	var env := Environment.new()

	# Sky
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.65, 0.78, 0.92)
	sky_mat.ground_bottom_color = Color(0.25, 0.40, 0.15)
	sky_mat.ground_horizon_color = Color(0.65, 0.78, 0.92)
	sky_mat.sun_angle_max = 30.0

	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	# Ambient light from sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Directional sun light
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.97, 0.88)
	sun.shadow_enabled = true
	add_child(sun)


func _start_singleplayer() -> void:
	network_manager.setup_singleplayer("Player 1")

	game_state = GameStateScript.new()
	game_state.course_seed = randi()

	var local_id: int = network_manager.get_my_peer_id()
	var player: PlayerState = PlayerStateScript.new()
	player.peer_id = local_id
	player.display_name = "Player 1"
	if golfer_stats:
		(golfer_stats as GolferStatsScript).apply_to(player)
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

	# Point camera toward the cup
	var to_cup: Vector3 = layout.cup_position - tee_position
	camera.camera_angle = atan2(-to_cup.x, -to_cup.z)
	var my_player: PlayerState = \
		game_state.players.get(network_manager.get_my_peer_id()) as PlayerState
	ball.setup_physics_params(my_player, layout.terrain_data)

	_show_hole_intro(_hole_number, _par)
	turn_manager.start_hole(tee_position)


func _on_ball_entered_cup() -> void:
	_spawn_cup_celebration(ball.global_position)
	var my_id: int = network_manager.get_my_peer_id()
	scoring_manager.complete_hole()
	turn_manager.notify_player_holed_out(my_id)


func _on_ball_at_rest(peer_id: int) -> void:
	_show_distance_to_hole()
	turn_manager.notify_ball_at_rest(peer_id)


func _on_ball_out_of_bounds(_peer_id: int) -> void:
	# Ball has already been teleported back to last_shot_position by golf_ball.gd.
	# The turn stays active — the player re-aims and shoots from there.
	_show_oob_message()


func _show_distance_to_hole() -> void:
	_hide_distance_label()
	if not current_hole:
		return
	var ball_pos: Vector3 = ball.global_position
	var cup_pos: Vector3 = current_hole.layout.cup_position
	var dist: float = Vector3(
		ball_pos.x - cup_pos.x, 0.0, ball_pos.z - cup_pos.z
	).length()
	# Don't show if already in the cup or very close
	if dist < 1.0:
		return
	_distance_label = Label.new()
	_distance_label.text = "%.1fm to pin" % dist
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.add_theme_font_size_override("font_size", 24)
	_distance_label.add_theme_color_override(
		"font_color", Color(1.0, 1.0, 1.0, 0.9)
	)
	_distance_label.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM
	)
	_distance_label.offset_top = -60.0
	$UICanvas.add_child(_distance_label)


func _hide_distance_label() -> void:
	if _distance_label and is_instance_valid(_distance_label):
		_distance_label.queue_free()
		_distance_label = null


func _spawn_cup_celebration(pos: Vector3) -> void:
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 60.0
	mat.initial_velocity_min = 4.0
	mat.initial_velocity_max = 8.0
	mat.gravity = Vector3(0.0, -5.0, 0.0)
	mat.scale_min = 0.8
	mat.scale_max = 1.5
	mat.color = Color(1.0, 0.85, 0.2)

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(1.0, 0.9, 0.3, 1.0))
	color_ramp.set_color(1, Color(1.0, 0.5, 0.1, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex

	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(1.0, 0.9, 0.3)
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat

	particles.process_material = mat
	particles.draw_pass_1 = mesh
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = 30
	particles.lifetime = 1.2
	particles.global_position = pos + Vector3(0.0, 0.5, 0.0)
	add_child(particles)
	get_tree().create_timer(2.5).timeout.connect(particles.queue_free)


func _show_hole_intro(hole_number: int, par: int) -> void:
	var label := Label.new()
	label.text = "Hole %d  —  Par %d" % [hole_number, par]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.modulate.a = 0.0
	$UICanvas.add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


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
	_scorecard.add_hole_result(
		course_manager.get_current_hole_number(), par, strokes, score_name
	)
	_scorecard.show_scorecard()
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
	_scorecard.hide_scorecard()
	if upgrade != null:
		var my_id: int = network_manager.get_my_peer_id()
		var player: PlayerState = game_state.players.get(my_id) as PlayerState
		if player:
			upgrade.apply(player)
			var td: RefCounted = null
			if current_hole and current_hole.layout:
				td = current_hole.layout.terrain_data
			ball.setup_physics_params(player, td)
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
	_hide_distance_label()
	scoring_manager.add_stroke()
	network_manager.submit_shot(direction, power)


func _on_shot_received(_peer_id: int, direction: Vector3, power: float) -> void:
	# Single-player: only one ball. Multiplayer: route by _peer_id to that player's ball node.
	ball.play_shot(direction, power)
