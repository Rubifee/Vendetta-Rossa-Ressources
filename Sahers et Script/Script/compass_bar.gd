extends Control

# ─────────────────────────────────────────────
#  EXPORTS
# ─────────────────────────────────────────────

## Nœud joueur (Node3D). Assigne-le dans l'inspecteur.
@export var player: Node3D

## Degrés visibles sur la barre (90 = quart du cercle).
@export var fov_degrees: float = 90.0

## ✅ POI définis directement dans l'inspecteur.
## Crée un nouveau CompassPOIData par point d'intérêt.
@export var points_of_interest: Array[CompassPOIData] = []

## Taille des icônes POI en pixels.
@export var icon_size: float = 32.0

## Afficher les labels sous les icônes.
@export var show_labels: bool = true

## Afficher les points cardinaux (N / E / S / O).
@export var show_cardinals: bool = true

## Afficher la distance sous chaque POI.
@export var show_distance: bool = false

## Afficher une flèche sur les bords quand un POI est hors champ.
@export var show_offscreen_arrows: bool = true

## Couleur du marqueur Nord.
@export var north_color: Color = Color(1.0, 0.2, 0.2)

## Couleur des autres cardinaux.
@export var cardinal_color: Color = Color(1.0, 1.0, 1.0)

## Couleur du texte des labels POI.
@export var label_color: Color = Color(1.0, 1.0, 1.0)

## Couleur des flèches hors-champ.
@export var arrow_color: Color = Color(1.0, 0.85, 0.0)


# ─────────────────────────────────────────────
#  INTERNES
# ─────────────────────────────────────────────

@onready var _poi_container: Control = $POI_Container
@onready var _strip: TextureRect = $CompassStrip

var _bar_width: float = 0.0

const _CARDINALS: Dictionary = {
	"N":   0.0,
	"E":  90.0,
	"S": 180.0,
	"O": -90.0
}


# ─────────────────────────────────────────────
#  CYCLE DE VIE
# ─────────────────────────────────────────────

func _ready() -> void:
	add_to_group("compass")
	clip_contents = true
	_bar_width = size.x
	resized.connect(_on_resized)
	_poi_container.clip_contents = true  # ← ajoute ça


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	_bar_width = size.x
	_rebuild_bar()


# ─────────────────────────────────────────────
#  REBUILD PRINCIPAL
# ─────────────────────────────────────────────

func _rebuild_bar() -> void:
	for child in _poi_container.get_children():
		child.queue_free()

	var yaw := _get_camera_yaw()

	_scroll_strip(yaw)
	_draw_pois(yaw)


# ─────────────────────────────────────────────
#  CARDINAUX
# ─────────────────────────────────────────────

# Dans _rebuild_bar(), remplace _draw_cardinals() par :
func _scroll_strip(player_yaw: float) -> void:
	if _strip == null or _strip.texture == null or _strip.material == null:
		return

	var normalized := wrapf(player_yaw, 0.0, 360.0) / 360.0
	var tw := float(_strip.texture.get_width())  # largeur réelle de la texture

	_strip.material.set_shader_parameter("offset",    normalized)
	_strip.material.set_shader_parameter("fov_ratio", fov_degrees / 360.0)
	_strip.material.set_shader_parameter("bar_width", _bar_width)
	_strip.material.set_shader_parameter("tex_width", tw)


# ─────────────────────────────────────────────
#  POI (depuis l'inspecteur)
# ─────────────────────────────────────────────

func _draw_pois(player_yaw: float) -> void:
	for poi: CompassPOIData in points_of_interest:
		if poi == null:
			continue

		var world_dir := poi.world_position - player.global_position
		world_dir.y = 0.0
		var distance := world_dir.length()

		if distance < 0.001:
			continue

		# Filtre distance max par POI.
		if poi.max_distance > 0.0 and distance > poi.max_distance:
			continue

		var world_angle := rad_to_deg(atan2(world_dir.x, -world_dir.z))  # ← plus de -
		var delta := wrapf(world_angle - player_yaw, -180.0, 180.0)
		var half_fov := fov_degrees / 2.0

		if abs(delta) <= half_fov:
			_place_poi(poi, delta, distance)
		elif show_offscreen_arrows:
			_place_offscreen_arrow(poi, delta)


func _place_poi(poi: CompassPOIData, delta: float, distance: float) -> void:
	var pos_x := _angle_to_x(delta)
	var cursor_y := 4.0

	if poi.icon != null:
		var tex := TextureRect.new()
		tex.texture = poi.icon
		tex.modulate = poi.color
		# Ces deux lignes sont la clé :
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(icon_size, icon_size)
		tex.size = Vector2(icon_size, icon_size)
		tex.position = Vector2(pos_x - icon_size / 2.0, cursor_y)
		_poi_container.add_child(tex)
		cursor_y += icon_size + 2.0
	else:
		var dot := _make_dot(pos_x, cursor_y + icon_size / 2.0, icon_size / 2.0, poi.color)
		_poi_container.add_child(dot)
		cursor_y += icon_size + 2.0

	if show_labels and poi.label != "":
		var lbl := _make_label(poi.label, pos_x, cursor_y, 10)
		lbl.modulate = label_color
		_poi_container.add_child(lbl)
		cursor_y += 14.0

	if show_distance:
		var lbl := _make_label("%.0fm" % distance, pos_x, cursor_y, 9)
		lbl.modulate = Color(0.8, 0.8, 0.8)
		_poi_container.add_child(lbl)


func _place_offscreen_arrow(poi: CompassPOIData, delta: float) -> void:
	var is_left := delta < 0.0
	var margin := 6.0
	var pos_x := margin if is_left else _bar_width - margin - 12.0

	var arrow := Label.new()
	arrow.text = "◀" if is_left else "▶"
	arrow.add_theme_font_size_override("font_size", 16)
	arrow.modulate = arrow_color
	arrow.position = Vector2(pos_x, (size.y - 20.0) / 2.0)
	_poi_container.add_child(arrow)

	if show_labels and poi.label != "":
		var offset_x := 20.0 if not is_left else -50.0
		var lbl := _make_label(poi.label, pos_x + offset_x + 25.0, (size.y - 14.0) / 2.0, 9)
		lbl.modulate = arrow_color
		_poi_container.add_child(lbl)


# ─────────────────────────────────────────────
#  API PUBLIQUE (ajout dynamique depuis le code)
# ─────────────────────────────────────────────

## Ajoute un POI dynamiquement depuis le code.
func add_poi(poi: CompassPOIData) -> void:
	if not points_of_interest.has(poi):
		points_of_interest.append(poi)


## Crée et ajoute un POI sans créer de resource manuellement.
func add_poi_at(world_pos: Vector3, icon: Texture2D = null, label: String = "", max_dist: float = 0.0) -> CompassPOIData:
	var poi := CompassPOIData.new()
	poi.world_position = world_pos
	poi.icon = icon
	poi.label = label
	poi.max_distance = max_dist
	points_of_interest.append(poi)
	return poi


## Retire un POI.
func remove_poi(poi: CompassPOIData) -> void:
	points_of_interest.erase(poi)


## Vide tous les POI.
func clear_pois() -> void:
	points_of_interest.clear()


# ─────────────────────────────────────────────
#  UTILITAIRES INTERNES
# ─────────────────────────────────────────────

func _get_camera_yaw() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam:
		return -rad_to_deg(cam.global_rotation.y)  # ← remet le -
	return -rad_to_deg(player.global_rotation.y)


func _angle_to_x(delta_deg: float) -> float:
	return ((delta_deg + fov_degrees / 2.0) / fov_degrees) * _bar_width


func _make_label(text: String, pos_x: float, pos_y: float, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.size = Vector2(60.0, float(font_size) + 4.0)
	lbl.position = Vector2(pos_x - 30.0, pos_y)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


func _make_dot(center_x: float, center_y: float, radius: float, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = Vector2(radius * 2.0, radius * 2.0)
	rect.position = Vector2(center_x - radius, center_y - radius)
	return rect


func _on_resized() -> void:
	_bar_width = size.x
	
