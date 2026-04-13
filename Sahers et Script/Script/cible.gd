# cible.gd
extends Node3D

@export var target:           Node3D
@export var airplane:         Node3D
@export var elastic_strength: float = 12.0
@export var damping:          float = 6.0
@export var max_distance:     float = 5.0
@export var deadzone:         float = 0.01

# Layer dédié pour l'overlay sans DOF.
# Dans Project Settings > Render > Layers, nomme ce layer "Cible" par exemple.
# Il doit être RETIRÉ du cull_mask de ta caméra principale (PlaneCamera).
const OVERLAY_LAYER := 20

var _velocity:     Vector3  = Vector3.ZERO
var _frozen_offset: Vector3 = Vector3.ZERO
var _frozen_basis:  Basis   = Basis()
var _was_free_look: bool    = false


func _ready() -> void:
	# ── Mesh sur le layer overlay uniquement ─────────────────────────────────
	for child in find_children("*", "MeshInstance3D"):
		var m := child as MeshInstance3D
		m.layers      = (1 << (OVERLAY_LAYER - 1))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := m.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.no_depth_test   = true
			mat.render_priority = 100

	# Lance la recherche de la caméra une fois l'arbre complet
	call_deferred("_setup_overlay_camera")


# ── Caméra overlay (sans environnement → sans DOF) ───────────────────────────
# Parentée à la PlaneCamera ; ne rend que le layer OVERLAY_LAYER.
# La PlaneCamera doit avoir ce layer retiré de son cull_mask (fait ici en code).
func _setup_overlay_camera() -> void:
	var main_cam := _find_camera(airplane)
	if not main_cam:
		push_warning("cible.gd : Camera3D introuvable sous 'airplane'.")
		return

	# Retire le layer overlay du rendu principal

	# Crée une caméra overlay enfant de la principale
	var oc            := Camera3D.new()
	oc.name           = "CibleOverlayCam"
	oc.cull_mask      = (1 << (OVERLAY_LAYER - 1))
	oc.environment    = null     # ← pas d'environnement = pas de DOF
	oc.fov            = main_cam.fov
	oc.near           = main_cam.near
	oc.far            = main_cam.far
	oc.keep_aspect    = main_cam.keep_aspect
	oc.current        = false    # ne détrône pas la caméra principale
	main_cam.add_child(oc)


# ── API publique : appelle set_active(false) à la sortie de l'avion ──────────
func set_active(enabled: bool) -> void:
	visible = enabled


func _process(delta: float) -> void:
	if not target or not airplane:
		return

	var free_look := Input.is_key_pressed(KEY_C)

	# ── C enfoncé : position + rotation figées par rapport à l'avion ─────────
	if free_look:
		if not _was_free_look:
			_frozen_offset = global_position - airplane.global_position
			_frozen_basis  = global_transform.basis
			_was_free_look = true

		global_position        = airplane.global_position + _frozen_offset
		global_transform.basis = _frozen_basis
		_velocity              = Vector3.ZERO
		return

	_was_free_look = false

	# ── Position élastique vers le target ─────────────────────────────────────
	var diff := target.global_position - global_position
	if diff.length() > deadzone:
		_velocity += diff * elastic_strength * delta
		_velocity -= _velocity * damping * delta
		global_position += _velocity * delta
	else:
		_velocity = Vector3.ZERO

	var offs := global_position - target.global_position
	if offs.length() > max_distance:
		global_position = target.global_position + offs.normalized() * max_distance

	# ── Rotation : look_at direct chaque frame (pas de slerp intermédiaire) ───
	if global_position.distance_to(airplane.global_position) > 0.001:
		look_at(airplane.global_position, Vector3.UP)


func _find_camera(root: Node) -> Camera3D:
	if root is Camera3D:
		return root as Camera3D
	for c in root.get_children():
		var r := _find_camera(c)
		if r:
			return r
	return null
