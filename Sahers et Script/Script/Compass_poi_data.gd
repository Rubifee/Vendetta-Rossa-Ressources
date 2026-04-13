## Resource représentant un point d'intérêt statique.
## Assigne-le dans l'inspecteur de CompassBar → points_of_interest.
class_name CompassPOIData
extends Resource

## Position dans le monde (x, y, z).
@export var world_position: Vector3 = Vector3.ZERO

## Icône affichée sur la boussole.
@export var icon: Texture2D = null

## Texte affiché sous l'icône (optionnel).
@export var label: String = ""

## Couleur de teinte appliquée sur l'icône.
@export var color: Color = Color.WHITE

## Distance max d'affichage en mètres (0 = toujours visible).
@export var max_distance: float = 0.0
