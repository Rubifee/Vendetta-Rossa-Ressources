## speedometer.gd
## Attache sur un Label (CanvasLayer ou HUD).
## Affiche la vitesse de l'avion en km/h quand le joueur est a bord.

extends Label

## RigidBody3D de l'avion (celui qui a buoyancy.gd)
@export var plane: RigidBody3D

## Format d'affichage. %d vitesse en km/h, %d hauteur en metres.
@export var display_format: String = "%d km/h\n%d m"

## Y de reference pour la hauteur (la surface de la mer).
## Laisse a 0.0 si ton eau est a Y=0, sinon assigne le Y de ton sea_node.
@export var sea_level: float = 0.0


func _process(_delta: float) -> void:
	if not plane:
		return

	var is_occupied: bool = plane.get("occupied")

	if not is_occupied:
		visible = false
		return

	visible = true
	var speed_kmh: int = int(plane.linear_velocity.length() * 3.6)
	var altitude:  int = int(plane.global_position.y - sea_level)
	text = display_format % [speed_kmh, altitude]
