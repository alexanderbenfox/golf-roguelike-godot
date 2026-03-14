class_name HoleState
extends RefCounted

# Per-hole layout data — generated deterministically from course_seed + hole index.
# Stored here so all clients can reconstruct the same layout.

var hole_number: int = 1        # 1-indexed for display
var par: int = 3
var tee_position: Vector3 = Vector3.ZERO
var cup_position: Vector3 = Vector3(0, 0.4, -20)

# Future: obstacle descriptors, terrain seed, fairway shape, etc.


func to_dict() -> Dictionary:
	return {
		"hole_number": hole_number,
		"par": par,
		"tee_position": {"x": tee_position.x, "y": tee_position.y, "z": tee_position.z},
		"cup_position": {"x": cup_position.x, "y": cup_position.y, "z": cup_position.z},
	}


static func from_dict(d: Dictionary) -> HoleState:
	var hs := HoleState.new()
	hs.hole_number = d["hole_number"]
	hs.par = d["par"]
	var tp: Dictionary = d["tee_position"]
	hs.tee_position = Vector3(tp["x"], tp["y"], tp["z"])
	var cp: Dictionary = d["cup_position"]
	hs.cup_position = Vector3(cp["x"], cp["y"], cp["z"])
	return hs
