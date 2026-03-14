class_name PlayerState
extends RefCounted

var peer_id: int = 1
var display_name: String = "Player"

# Ball position on current hole
var ball_position: Vector3 = Vector3.ZERO

# Scoring
var strokes_this_hole: int = 0
var total_strokes: int = 0
var is_hole_complete: bool = false

# Roguelike modifiers — applied when building PhysicsParams
var power_multiplier: float = 1.0
var friction_modifier: float = 1.0
var bounce_modifier: float = 1.0


func reset_for_hole(start_pos: Vector3) -> void:
	ball_position = start_pos
	strokes_this_hole = 0
	is_hole_complete = false


func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"display_name": display_name,
		"ball_position": {"x": ball_position.x, "y": ball_position.y, "z": ball_position.z},
		"strokes_this_hole": strokes_this_hole,
		"total_strokes": total_strokes,
		"is_hole_complete": is_hole_complete,
		"power_multiplier": power_multiplier,
		"friction_modifier": friction_modifier,
		"bounce_modifier": bounce_modifier,
	}


static func from_dict(d: Dictionary) -> PlayerState:
	var ps := PlayerState.new()
	ps.peer_id = d["peer_id"]
	ps.display_name = d["display_name"]
	var bp: Dictionary = d["ball_position"]
	ps.ball_position = Vector3(bp["x"], bp["y"], bp["z"])
	ps.strokes_this_hole = d["strokes_this_hole"]
	ps.total_strokes = d["total_strokes"]
	ps.is_hole_complete = d["is_hole_complete"]
	ps.power_multiplier = d["power_multiplier"]
	ps.friction_modifier = d["friction_modifier"]
	ps.bounce_modifier = d["bounce_modifier"]
	return ps
