# orbit_camera.gd
extends Node3D

@export var target:      Node3D
@export var look_speed:  float = 0.002
@export var min_pitch:   float = -60.0
@export var max_pitch:   float = 80.0

var _pitch: float = 0.0
var _yaw:   float = 0.0
var _active: bool = false

# ── Free-look (touche C) ────────────────────────────────────────────────────
# Les inputs souris sont redirigés vers ces variables temporaires
# pendant que C est tenu. À la release, la caméra retrouve _yaw/_pitch
# qui n'ont jamais changé → retour instantané à l'angle d'avant C.
var _free_yaw:     float = 0.0
var _free_pitch:   float = 0.0
var _in_free_look: bool  = false


func activate() -> void:
	_yaw   = target.global_rotation.y + PI   # démarre derrière l'avion
	_pitch = deg_to_rad(-20.0)
	$PlaneCamera.make_current()
	_active = true


func deactivate(restore_cam: Camera3D) -> void:
	_active = false
	restore_cam.make_current()


func _process(_delta: float) -> void:
	if not _active or not target:
		return

	var free_look_now := Input.is_key_pressed(KEY_C)

	if free_look_now and not _in_free_look:
		# C vient d'être enfoncé : initialise les angles temporaires
		_free_yaw     = _yaw
		_free_pitch   = _pitch
		_in_free_look = true
	elif not free_look_now and _in_free_look:
		# C vient d'être relâché : abandonne les angles temporaires
		# _yaw/_pitch sont intacts → la caméra revient à sa rotation d'avant
		_in_free_look = false

	# Suit la position de l'avion, ignore sa rotation
	global_position = target.global_position

	# Applique les angles courants (temporaires si free-look, réels sinon)
	var cur_yaw   := _free_yaw   if _in_free_look else _yaw
	var cur_pitch := _free_pitch if _in_free_look else _pitch
	rotation.x = -cur_pitch
	rotation.y = cur_yaw


func add_input(rel: Vector2) -> void:
	if not _active:
		return

	if _in_free_look:
		# Pendant C : on tourne les variables temporaires seulement
		_free_pitch -= rel.y * look_speed
		_free_pitch  = clamp(_free_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		_free_yaw   -= rel.x * look_speed
	else:
		# Mode normal : on tourne les variables permanentes
		_pitch -= rel.y * look_speed
		_pitch  = clamp(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		_yaw   -= rel.x * look_speed
