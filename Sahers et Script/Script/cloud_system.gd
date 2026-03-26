## CloudSystem.gd
## Attache ce script à un Node3D dans ta scène.
## Les nuages sont stables dans le monde : définis par une noise map en coordonnées
## "virtuelles", puis décalés par le vent. Aucun bug visuel quand le joueur se déplace.
## Tous les paramètres du shader sont contrôlables depuis l'inspecteur.

extends Node3D


# ──────────────────────────────────────────────
#  PARAMÈTRES EXPORTÉS — SYSTÈME
# ──────────────────────────────────────────────

@export_group("Références")
## Chemin vers le nœud joueur (Node3D).
@export var player_path: NodePath = NodePath("")
## DirectionalLight3D de la scène (optionnel). Si assigné, synchronise light_dir automatiquement.
@export var directional_light: DirectionalLight3D

@export_group("Meshes des nuages")
## MeshInstance3D déjà dans la scène utilisés comme templates (seront cachés au démarrage).
@export var cloud_instances: Array[NodePath] = []

@export_group("Placement")
@export var cloud_y: float = 120.0
@export var view_distance: float = 900.0
@export var grid_cell_size: float = 80.0

@export_group("Noise")
@export var noise_seed: int = 42
@export var noise_frequency: float = 0.008
@export var cloud_threshold: float = 0.45

@export_group("Taille des nuages")
@export var min_cloud_scale: float = 0.8
@export var max_cloud_scale: float = 3.5
@export var y_scale_variation: float = 0.3

@export_group("Vent")
@export var wind_direction: Vector2 = Vector2(1.0, 0.3)
@export var wind_speed: float = 4.0

# ──────────────────────────────────────────────
#  PARAMÈTRES EXPORTÉS — SHADER
# ──────────────────────────────────────────────

@export_group("Shader / Forme")
## Densité globale du nuage. Plus élevé = plus opaque.
@export_range(0.0, 2.0) var shader_density: float = 1.0
## Douceur des bords (plus élevé = bords plus flous).
@export_range(0.01, 1.0) var shader_edge_softness: float = 0.45
## Puissance de l'arrondi sphérique (plus élevé = bords plus durs).
@export_range(0.5, 8.0) var shader_sphere_power: float = 2.0
## Décalage du centre de la forme (asymétrie légère).
@export var shader_shape_offset: Vector3 = Vector3(0.0, -0.1, 0.0)

@export_group("Shader / Noise")
## Fréquence du bruit principal (forme générale des grumeaux).
@export_range(0.1, 5.0) var shader_noise_scale: float = 1.8
## Fréquence du bruit de détail (petits grumeaux).
@export_range(1.0, 10.0) var shader_detail_scale: float = 4.5
## Force du détail (0 = lisse, 1 = très grumeleux).
@export_range(0.0, 1.0) var shader_detail_strength: float = 0.35
## Vitesse d'animation interne du nuage (0 = statique).
@export_range(0.0, 1.0) var shader_noise_speed: float = 0.04

@export_group("Shader / Couleurs")
## Couleur lumineuse du dessus.
@export var shader_color_top: Color = Color(1.0, 1.0, 1.0, 1.0)
## Couleur sombre du dessous (ombre).
@export var shader_color_bottom: Color = Color(0.72, 0.78, 0.85, 1.0)
## Couleur du halo sur le bord éclairé.
@export var shader_color_rim: Color = Color(1.0, 1.0, 1.0, 0.6)
## Direction manuelle de la lumière (ignorée si directional_light est assigné).
@export var shader_light_dir: Vector3 = Vector3(0.4, 0.9, 0.2)
## Force du dégradé haut/bas.
@export_range(0.0, 1.0) var shader_shading_strength: float = 0.55

@export_group("Shader / Transparence")
## Opacité globale.
@export_range(0.0, 1.0) var shader_opacity: float = 0.92
## Distance à partir de laquelle le fondu commence.
@export_range(50.0, 2000.0) var shader_fade_start: float = 600.0
## Distance maximale de visibilité (fondu complet).
@export_range(100.0, 3000.0) var shader_fade_distance: float = 1200.0

# ──────────────────────────────────────────────
#  VARIABLES INTERNES
# ──────────────────────────────────────────────

var _noise: FastNoiseLite
var _wind_offset: Vector2 = Vector2.ZERO
var _active_clouds: Dictionary = {}
var _player: Node3D
var _wind_dir_normalized: Vector2 = Vector2.ZERO
var _cloud_templates: Array[Node3D] = []

# ──────────────────────────────────────────────
#  INITIALISATION
# ──────────────────────────────────────────────

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed if noise_seed != 0 else randi()
	_noise.frequency = noise_frequency

	_wind_dir_normalized = wind_direction.normalized()

	if not player_path.is_empty():
		_player = get_node_or_null(player_path)
		if _player == null:
			push_warning("CloudSystem: player_path introuvable.")

	for path in cloud_instances:
		var node := get_node_or_null(path)
		if node == null:
			push_warning("CloudSystem: NodePath introuvable → " + str(path))
			continue
		if not (node is MeshInstance3D):
			push_warning("CloudSystem: le nœud n'est pas un MeshInstance3D → " + str(path))
			continue
		node.visible = false
		_cloud_templates.append(node as Node3D)

	if _cloud_templates.is_empty():
		push_error("CloudSystem: aucun template valide ! Vérifie cloud_instances.")

# ──────────────────────────────────────────────
#  BOUCLE PRINCIPALE
# ──────────────────────────────────────────────

func _process(delta: float) -> void:
	if _cloud_templates.is_empty():
		return

	_wind_offset += _wind_dir_normalized * wind_speed * delta

	var player_world_pos := Vector3.ZERO
	if _player:
		player_world_pos = _player.global_position

	_update_active_cells(player_world_pos)

	# Direction lumière : depuis la DirectionalLight si assignée, sinon paramètre manuel
	var light_dir := shader_light_dir
	if directional_light:
		light_dir = -directional_light.global_basis.z

	# Déplacer les nuages et mettre à jour les paramètres shader en temps réel
	for cell: Vector2i in _active_clouds:
		var cloud: Node3D = _active_clouds[cell]
		if not is_instance_valid(cloud):
			continue

		# Déplacement vent
		var virt := _cell_virtual_center(cell)
		cloud.global_position = Vector3(
			virt.x + _wind_offset.x,
			cloud_y,
			virt.y + _wind_offset.y
		)

		# Mise à jour shader
		_apply_shader_params(cloud, light_dir)

# ──────────────────────────────────────────────
#  APPLICATION DES PARAMÈTRES SHADER
# ──────────────────────────────────────────────

## Applique tous les paramètres shader exportés sur le MeshInstance3D (ou ses enfants).
func _apply_shader_params(node: Node3D, light_dir: Vector3) -> void:
	# On cherche tous les MeshInstance3D dans le nœud (lui-même + enfants)
	var targets: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		targets.append(node as MeshInstance3D)
	for child in node.get_children():
		if child is MeshInstance3D:
			targets.append(child as MeshInstance3D)

	for mi: MeshInstance3D in targets:
		var mat := mi.get_active_material(0)
		if mat == null or not (mat is ShaderMaterial):
			continue
		var sm := mat as ShaderMaterial
		sm.set_shader_parameter("density",           shader_density)
		sm.set_shader_parameter("edge_softness",     shader_edge_softness)
		sm.set_shader_parameter("sphere_power",      shader_sphere_power)
		sm.set_shader_parameter("shape_offset",      shader_shape_offset)
		sm.set_shader_parameter("noise_scale",       shader_noise_scale)
		sm.set_shader_parameter("detail_scale",      shader_detail_scale)
		sm.set_shader_parameter("detail_strength",   shader_detail_strength)
		sm.set_shader_parameter("noise_speed",       shader_noise_speed)
		sm.set_shader_parameter("color_top",         shader_color_top)
		sm.set_shader_parameter("color_bottom",      shader_color_bottom)
		sm.set_shader_parameter("color_rim",         shader_color_rim)
		sm.set_shader_parameter("light_dir",         light_dir)
		sm.set_shader_parameter("shading_strength",  shader_shading_strength)
		sm.set_shader_parameter("opacity",           shader_opacity)
		sm.set_shader_parameter("fade_start",        shader_fade_start)
		sm.set_shader_parameter("fade_distance",     shader_fade_distance)

# ──────────────────────────────────────────────
#  GESTION DES CELLULES
# ──────────────────────────────────────────────

func _update_active_cells(player_world_pos: Vector3) -> void:
	var virt_player := Vector2(
		player_world_pos.x - _wind_offset.x,
		player_world_pos.z - _wind_offset.y
	)

	var center_cell := Vector2i(
		int(floor(virt_player.x / grid_cell_size)),
		int(floor(virt_player.y / grid_cell_size))
	)

	var half := int(ceil(view_distance / grid_cell_size)) + 1

	var cells_needed: Dictionary = {}
	for dx in range(-half, half + 1):
		for dz in range(-half, half + 1):
			var cell := Vector2i(center_cell.x + dx, center_cell.y + dz)
			var virt := _cell_virtual_center(cell)
			var world_x := virt.x + _wind_offset.x
			var world_z := virt.y + _wind_offset.y
			if abs(world_x - player_world_pos.x) <= view_distance \
			and abs(world_z - player_world_pos.z) <= view_distance:
				cells_needed[cell] = true

	for cell: Vector2i in _active_clouds.keys():
		if not cells_needed.has(cell):
			var cloud: Node3D = _active_clouds[cell]
			if is_instance_valid(cloud):
				cloud.queue_free()
			_active_clouds.erase(cell)

	for cell: Vector2i in cells_needed:
		if _active_clouds.has(cell):
			continue
		_try_spawn_cloud(cell)

func _try_spawn_cloud(cell: Vector2i) -> void:
	var virt := _cell_virtual_center(cell)

	var raw_noise: float = _noise.get_noise_2d(virt.x, virt.y)
	var noise_val: float = (raw_noise + 1.0) * 0.5

	if noise_val < cloud_threshold:
		return

	var tmpl_idx: int = (_cell_hash(cell) % 10000) % _cloud_templates.size()
	var template: Node3D = _cloud_templates[tmpl_idx]

	var t: float = (noise_val - cloud_threshold) / (1.0 - cloud_threshold)
	var scale_val: float = lerp(min_cloud_scale, max_cloud_scale, t)

	var y_rand: float = float(_cell_hash(cell + Vector2i(7, 13)) % 10000) / 10000.0 * 2.0 - 1.0
	var scale_y: float = scale_val * (1.0 + y_rand * y_scale_variation)

	var cloud: Node3D = template.duplicate() as Node3D
	cloud.visible = true
	cloud.scale = Vector3(scale_val, scale_y, scale_val)

	add_child(cloud)

	var world_x := virt.x + _wind_offset.x
	var world_z := virt.y + _wind_offset.y
	cloud.global_position = Vector3(world_x, cloud_y, world_z)

	# Appliquer les paramètres shader immédiatement au spawn
	var light_dir := shader_light_dir
	if directional_light:
		light_dir = -directional_light.global_basis.z
	_apply_shader_params(cloud, light_dir)

	_active_clouds[cell] = cloud

# ──────────────────────────────────────────────
#  UTILITAIRES
# ──────────────────────────────────────────────

func _cell_virtual_center(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * grid_cell_size,
		(float(cell.y) + 0.5) * grid_cell_size
	)

func _cell_hash(cell: Vector2i) -> int:
	var h: int = cell.x * 1610612741 ^ cell.y * 805306457
	h ^= h >> 16
	h *= 0x45d9f3b
	h ^= h >> 16
	return abs(h)
