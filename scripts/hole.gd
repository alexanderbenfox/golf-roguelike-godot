class_name Hole
extends Node3D

signal ball_entered_cup

@export var par: int = 3
@export var hole_number: int = 1

@onready var cup: Area3D
@onready var cup_collision: CollisionShape3D

var cup_radius = 0.4
var cup_height = 0.4

func _ready() -> void:
	create_cup()

func create_cup() -> void:
	cup = Area3D.new()
	cup.name = "Cup"
	add_child(cup)

	#create collision shape
	cup_collision = CollisionShape3D.new()
	var cylinder_shape = CylinderShape3D.new()
	cylinder_shape.radius = cup_radius
	cylinder_shape.height = cup_height
	cup_collision.shape = cylinder_shape
	cup.add_child(cup_collision)

	# position cup slightly below ground
	cup.position = Vector3(0, 0, 0)

	# connect signal
	cup.body_entered.connect(_on_body_entered_cup)

	# create visual
	create_cup_visual()

func create_cup_visual():
	# Create a simple cylinder for the hole
	var mesh_instance = MeshInstance3D.new()
	cup.add_child(mesh_instance)
	
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = cup_radius
	cylinder_mesh.bottom_radius = cup_radius
	cylinder_mesh.height = cup_height
	mesh_instance.mesh = cylinder_mesh

	# Make it black (hole in ground)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	mesh_instance.material_override = material

	# Add a flag pole (optional but helps visibility)
	create_flag()

func create_flag():
	# Flag pole
	var pole = MeshInstance3D.new()
	cup.add_child(pole)

	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.01
	pole_mesh.bottom_radius = 0.01
	pole_mesh.height = 2.0
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 1.0, 0)

	var pole_material = StandardMaterial3D.new()
	pole_material.albedo_color = Color.WHITE
	pole.material_override = pole_material

	# Flag
	var flag = MeshInstance3D.new()
	cup.add_child(flag)

	var flag_mesh = BoxMesh.new()
	flag_mesh.size = Vector3(0.5, 0.3, 0.02)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.25, 1.85, 0)

	var flag_material = StandardMaterial3D.new()
	flag_material.albedo_color = Color.RED
	flag.material_override = flag_material

func _on_body_entered_cup(body):
	if body.is_in_group("ball"):
		# Check if ball is moving slowly enough to count
		if body is RigidBody3D:
			if body.linear_velocity.length() < 2.0:  # Must be moving slowly
				ball_entered_cup.emit()
				print("Hole in one! (or " + str(body.name) + " entered cup)")

func set_cup_position(pos: Vector3):
	if cup:
		cup.global_position = pos
