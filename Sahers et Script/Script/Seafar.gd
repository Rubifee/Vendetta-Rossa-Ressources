extends Node3D

@export var player: CharacterBody3D
@export var plane_world_size: float = 200.0  # taille réelle du plane en unités Godot
var _last_pos: Vector3

func _ready() -> void:
	if player:
		_last_pos = player.global_position

func _process(_delta: float) -> void:
	if not player:
		return

	var moved := Vector2(
		player.global_position.x - _last_pos.x,
		player.global_position.z - _last_pos.z
	)
	_last_pos = player.global_position

	if moved.length_squared() == 0.0:
		return

	var mat := (get_node("Plane") as MeshInstance3D).get_active_material(0)
	var current = mat.get_shader_parameter("uv_offset")
	if current == null: current = Vector2.ZERO

	# 1 unité monde = 1/plane_world_size en UV
	# signe positif : le plane suit le joueur → la texture doit avancer dans le même sens
	var delta_uv := moved / plane_world_size
	mat.set_shader_parameter("uv_offset", (current as Vector2) + delta_uv)
