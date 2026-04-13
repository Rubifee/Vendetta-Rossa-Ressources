## PropellerController.gd
## À attacher sur le Node3D PARENT des pièces d'hélice.
##
## Hiérarchie attendue :
##   Hélices (Node3D)        ← CE SCRIPT ici
##   ├── Hélice1 (MeshInstance3D)
##   ├── Hélice2 (MeshInstance3D)
##   └── BlurDisc (Sprite3D)
##
## La rotation s'applique sur le Node3D parent → les deux meshes tournent ensemble.
## Le fondu gère les matériaux de TOUTES les pièces listées dans mesh_parts.

extends Node3D

# ═══════════════════════════════════════════════════════════════════════════════
# RÉFÉRENCES
# ═══════════════════════════════════════════════════════════════════════════════
@export_group("Références")
## Le RigidBody3D qui porte buoyancy.gd (pour lire occupied + throttle).
@export var airplane_body: RigidBody3D
## Toutes les pièces MeshInstance3D de l'hélice (Hélice1, Hélice2…).
@export var mesh_parts: Array[MeshInstance3D] = []
## Le Sprite3D / MeshInstance3D du disque flou (BlurDisc).
@export var blur_disc_node: Node3D
## Axe de rotation LOCAL (Z = axe moteur en général, X ou Y selon ton modèle).
@export var rotation_axis: Vector3 = Vector3(0.0, 0.0, 1.0)

# ═══════════════════════════════════════════════════════════════════════════════
# RPM
# ═══════════════════════════════════════════════════════════════════════════════
@export_group("RPM")
@export_range(100.0, 3000.0, 10.0) var max_rpm:         float = 1200.0
@export_range(0.5,   30.0,   0.5)  var spool_up_time:   float = 4.0
@export_range(1.0,   60.0,   1.0)  var spool_down_time: float = 8.0
@export_range(0.0, 1000.0,  10.0)  var idle_rpm:        float = 300.0

# ═══════════════════════════════════════════════════════════════════════════════
# FONDU MESH ↔ DISQUE
# ═══════════════════════════════════════════════════════════════════════════════
@export_group("Fondu")
@export_range(0.0, 3000.0, 10.0) var fade_start_rpm: float = 200.0
@export_range(0.0, 3000.0, 10.0) var fade_end_rpm:   float = 600.0

# ═══════════════════════════════════════════════════════════════════════════════
# DISQUE FLOU
# ═══════════════════════════════════════════════════════════════════════════════
@export_group("Disque flou")
@export_range(0.0, 20.0, 0.1) var disc_visual_speed: float = 3.0

# ═══════════════════════════════════════════════════════════════════════════════
# ÉTAT INTERNE
# ═══════════════════════════════════════════════════════════════════════════════
var _current_rpm:    float                     = 0.0
var _engine_running: bool                      = false
var _part_materials: Array[StandardMaterial3D] = []
var _disc_material:  StandardMaterial3D        = null

# ═══════════════════════════════════════════════════════════════════════════════
# INIT
# ═══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	_part_materials.clear()
	for mi: MeshInstance3D in mesh_parts:
		var base := mi.get_active_material(0)
		var mat: StandardMaterial3D
		if base is StandardMaterial3D:
			mat = base.duplicate() as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()
		mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.flags_transparent = true
		mi.set_surface_override_material(0, mat)
		_part_materials.append(mat)

	if blur_disc_node:
		if blur_disc_node is MeshInstance3D:
			var mi := blur_disc_node as MeshInstance3D
			var base := mi.get_active_material(0)
			if base is StandardMaterial3D:
				_disc_material = base.duplicate() as StandardMaterial3D
			else:
				_disc_material = StandardMaterial3D.new()
			_disc_material.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
			_disc_material.flags_transparent = true
			_disc_material.shading_mode      = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.set_surface_override_material(0, _disc_material)
		blur_disc_node.visible = false

	if mesh_parts.is_empty():
		push_warning("[PropellerController] mesh_parts est vide !")
	if not airplane_body:
		push_warning("[PropellerController] airplane_body non assigné !")


# ═══════════════════════════════════════════════════════════════════════════════
# BOUCLE
# ═══════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	_update_engine_state()
	_update_rpm(delta)
	_rotate_group(delta)
	_update_visuals()
	if blur_disc_node:
		_rotate_disc(delta)

func _update_engine_state() -> void:
	if not airplane_body:
		_engine_running = false
		return
	_engine_running = airplane_body.get("occupied") as bool

func _update_rpm(delta: float) -> void:
	var throttle: float = 1.0 if (_engine_running and Input.is_key_pressed(KEY_Z)) else 0.0
	var target_rpm: float = lerpf(idle_rpm, max_rpm, throttle) if _engine_running else 0.0
	var time_const: float = (spool_up_time if _current_rpm < target_rpm else spool_down_time) / log(100.0)
	var alpha: float = 1.0 - exp(-delta / maxf(time_const, 0.0001))
	_current_rpm = clampf(lerpf(_current_rpm, target_rpm, alpha), 0.0, max_rpm)

func _rotate_group(delta: float) -> void:
	var rads_per_sec: float = (_current_rpm / 60.0) * TAU
	rotate(rotation_axis.normalized(), rads_per_sec * delta)

func _update_visuals() -> void:
	var range_rpm: float  = maxf(fade_end_rpm - fade_start_rpm, 1.0)
	var t: float          = clampf((_current_rpm - fade_start_rpm) / range_rpm, 0.0, 1.0)
	var mesh_alpha: float = 1.0 - t

	for mat: StandardMaterial3D in _part_materials:
		var col: Color = mat.albedo_color
		col.a = mesh_alpha
		mat.albedo_color = col

	if blur_disc_node:
		blur_disc_node.visible = t > 0.001
		if _disc_material:
			var col: Color = _disc_material.albedo_color
			col.a = t
			_disc_material.albedo_color = col
		elif blur_disc_node is Sprite3D:
			(blur_disc_node as Sprite3D).modulate.a = t

func _rotate_disc(delta: float) -> void:
	blur_disc_node.rotate(rotation_axis.normalized(), disc_visual_speed * delta)

# ═══════════════════════════════════════════════════════════════════════════════
# API PUBLIQUE
# ═══════════════════════════════════════════════════════════════════════════════
func kill_engine() -> void:
	_engine_running = false
	_current_rpm    = 0.0

func get_rpm() -> float:
	return _current_rpm
