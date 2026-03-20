## HazardWarningDisc — reusable pulsing ground indicator for hazard zones.
##
## Handles idle/warning/active color transitions with configurable pulse.
## Supports both circular (CylinderMesh) and rectangular (BoxMesh) shapes.
class_name HazardWarningDisc
extends MeshInstance3D

var _material: StandardMaterial3D
var _idle_color: Color
var _active_color: Color


## Create the disc mesh and material.
## When rect_size is non-zero, uses a BoxMesh instead of a CylinderMesh.
func setup(
	radius: float,
	idle_color: Color,
	active_color: Color,
	rect_size: Vector2 = Vector2.ZERO,
) -> void:
	_idle_color = idle_color
	_active_color = active_color

	if rect_size != Vector2.ZERO:
		var box := BoxMesh.new()
		box.size = Vector3(rect_size.x, 0.05, rect_size.y)
		mesh = box
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.05
		mesh = cyl

	_material = StandardMaterial3D.new()
	_material.albedo_color = idle_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = _material
	position.y = 0.03


## Update color based on state. For WARNING, pass accumulated time for pulse.
func set_state(state: int, pulse_time: float = 0.0) -> void:
	match state:
		0:  # IDLE
			_material.albedo_color = _idle_color
		1:  # WARNING
			var pulse: float = 0.5 + 0.5 * sin(pulse_time * 8.0)
			_material.albedo_color = Color(
				lerpf(_idle_color.r, _active_color.r, pulse),
				lerpf(_idle_color.g, _active_color.g, pulse),
				lerpf(_idle_color.b, _active_color.b, pulse),
				lerpf(_idle_color.a, _active_color.a, pulse),
			)
		2:  # ACTIVE
			_material.albedo_color = _active_color
