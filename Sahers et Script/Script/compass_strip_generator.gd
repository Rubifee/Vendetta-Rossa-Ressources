## compass_strip_generator.gd
## Attache ce script à un nœud quelconque dans ta scène (ex: CompassBar).
## Il génère la texture de la bande de boussole au démarrage et la sauvegarde
## dans res://assets/ui/compass_strip.png.
## Tu peux ensuite l'assigner au TextureRect CompassStrip dans l'inspecteur.
##
## Pour regénérer : relance simplement la scène.

@tool  # Permet de l'exécuter directement dans l'éditeur si besoin.
extends Node

# ─────────────────────────────────────────────
#  PARAMÈTRES DE GÉNÉRATION
# ─────────────────────────────────────────────

## Largeur totale de la texture (doit représenter 360°).
@export var texture_width: int  = 1024
## Hauteur de la texture.
@export var texture_height: int = 64
## Chemin de sauvegarde.
@export var save_path: String   = "res://assets/ui/compass_strip.png"

## Couleur de fond (transparent recommandé).
@export var color_background: Color = Color(0.0, 0.0, 0.0, 0.0)
## Couleur des petits traits de graduation.
@export var color_tick_minor: Color = Color(1.0, 1.0, 1.0, 0.6)
## Couleur des grands traits (cardinaux / inter-cardinaux).
@export var color_tick_major: Color = Color(1.0, 1.0, 1.0, 1.0)
## Couleur du marqueur Nord.
@export var color_north: Color      = Color(1.0, 0.25, 0.25, 1.0)
## Couleur du texte.
@export var color_text: Color       = Color(1.0, 1.0, 1.0, 1.0)
## Couleur du texte Nord.
@export var color_text_north: Color = Color(1.0, 0.25, 0.25, 1.0)

## Génère et sauvegarde automatiquement au _ready.
@export var auto_generate: bool = true
@export var reference_bar_width: int = 600
@export var fov_degrees: float = 75

# ─────────────────────────────────────────────
#  POINTS CARDINAUX  (angle → label)
# ─────────────────────────────────────────────

const DIRECTIONS: Dictionary = {
	  0: "N",
	 45: "NO",
	 90: "O",
	135: "SO",
	180: "S",
	225: "SE",
	270: "E",
	315: "NE",
}


# ─────────────────────────────────────────────
#  CYCLE
# ─────────────────────────────────────────────

func _ready() -> void:
	if auto_generate:
		generate_and_save()


# ─────────────────────────────────────────────
#  GÉNÉRATION
# ─────────────────────────────────────────────

func generate_and_save() -> ImageTexture:
	texture_width = int(reference_bar_width * 360.0 / fov_degrees)
	var img := Image.create(texture_width, texture_height, false, Image.FORMAT_RGBA8)
	img.fill(color_background)

	# Dessine une graduation toutes les 5°.
	for deg in range(0, 360, 5):
		var x := int((float(deg) / 360.0) * texture_width)
		var is_cardinal       := deg % 90 == 0
		var is_intercardinal  := deg % 45 == 0
		var is_major          := deg % 10 == 0

		var tick_color := color_north if deg == 0 else \
						  color_tick_major if (is_cardinal or is_intercardinal) else \
						  color_tick_minor if is_major else \
						  Color(1, 1, 1, 0.25)

		var tick_h := 24 if (is_cardinal or is_intercardinal) else \
					  14 if is_major else 8

		_draw_vertical_line(img, x, texture_height - tick_h - 2, texture_height - 2, tick_color)

	# Dessine les labels texte.
	for deg in DIRECTIONS:
		var label: String = DIRECTIONS[deg]
		var x := int((float(deg) / 360.0) * texture_width)
		var txt_color := color_text_north if deg == 0 else color_text
		_draw_text(img, label, x, 8, txt_color)

	# Sauvegarde sur disque.
	_ensure_directory(save_path)
	var err := img.save_png(ProjectSettings.globalize_path(save_path))
	if err != OK:
		push_error("CompassStripGenerator: impossible de sauvegarder → " + save_path)


	var tex := ImageTexture.create_from_image(img)

	# Assigne directement au TextureRect frère si présent.
	_auto_assign(tex)

	return tex


# ─────────────────────────────────────────────
#  DESSIN
# ─────────────────────────────────────────────

func _draw_vertical_line(img: Image, x: int, y_start: int, y_end: int, color: Color) -> void:
	for y in range(y_start, y_end + 1):
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			img.set_pixel(x, y, color)
		# Double épaisseur pour les cardinaux.
		if x + 1 < img.get_width():
			img.set_pixel(x + 1, y, color)


## Dessin de texte pixel-art (bitmap 3×5 minimaliste).
## Dessin de texte pixel-art — chaque pixel de la fonte est rendu en (scale × scale).
func _draw_text(img: Image, text: String, center_x: int, y: int, color: Color, scale: int = 2) -> void:
	var char_w  := (3 + 1) * scale   # 3 px large + 1 px espacement, mis à l'échelle
	var total_w := text.length() * char_w - scale
	@warning_ignore("integer_division")
	var start_x := center_x - total_w / 2

	for i in range(text.length()):
		_draw_char(img, text[i], start_x + i * char_w, y, color, scale)


func _draw_char(img: Image, c: String, x: int, y: int, color: Color, scale: int = 2) -> void:
	const FONT: Dictionary = {
		"N": [0b111, 0b101, 0b101, 0b101, 0b101],
		"E": [0b111, 0b100, 0b110, 0b100, 0b111],
		"S": [0b111, 0b100, 0b111, 0b001, 0b111],
		"O": [0b010, 0b101, 0b101, 0b101, 0b010],
		"I": [0b010, 0b010, 0b010, 0b010, 0b010],
		"R": [0b110, 0b101, 0b110, 0b101, 0b101],
	}

	if c not in FONT:
		return

	var rows: Array = FONT[c]
	for row_i in range(rows.size()):
		var bits: int = rows[row_i]
		for col in range(3):
			if bits & (1 << (2 - col)):
				# Dessine un bloc scale×scale pour chaque pixel de la fonte.
				for dy in range(scale):
					for dx in range(scale):
						_set_px(img, x + col * scale + dx, y + row_i * scale + dy, color)


## Dessine un mot entier pré-défini pixel par pixel (pour les diagonales).
func _draw_word_bitmap(img: Image, bitmap: Array, x: int, y: int, color: Color) -> void:
	for row_i in range(bitmap.size()):
		var row: Array = bitmap[row_i]
		for col in range(row.size()):
			if row[col] == 1:
				_set_px(img, x + col, y + row_i, color)


func _set_px(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)


# ─────────────────────────────────────────────
#  UTILITAIRES
# ─────────────────────────────────────────────

func _ensure_directory(path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


## Si un TextureRect nommé "CompassStrip" est frère de ce nœud, on lui assigne la texture.
func _auto_assign(tex: ImageTexture) -> void:
	var strip := get_parent().get_node_or_null("CompassStrip")
	if strip and strip is TextureRect:
		strip.texture = tex
