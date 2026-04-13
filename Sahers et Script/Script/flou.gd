# blur_controller.gd - à attacher sur n'importe quel Node (ex: WorldEnvironment)
extends Node

@export var player: Node3D
@export var environment: WorldEnvironment

var _effect: BlurSphereEffect  # nom de ta classe

func _ready() -> void:
	# Récupère l'effet dans le compositor
	for effect in environment.compositor.compositor_effects:
		if effect is BlurSphereEffect:
			_effect = effect
			break

func _process(_delta: float) -> void:
	if _effect and player:
		_effect.player_world_pos = player.global_position
