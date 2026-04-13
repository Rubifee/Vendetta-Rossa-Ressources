extends Node3D
@export var player: CharacterBody3D

func _process(_delta: float) -> void:
	if not player:
		return
	global_position = Vector3(
		player.global_position.x,
		global_position.y,  # Y reste inchangé
		player.global_position.z
	)
