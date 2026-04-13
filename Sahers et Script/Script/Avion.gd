## buoyancy.gd
## Attache sur le RigidBody3D de l'avion.
## Flottaison par viewport-shader + vol autopilote style MouseFlight (War Thunder).
extends RigidBody3D

# ═══════════════════════════════════════════════════════════════════════════════
# EXPORTS
# ═══════════════════════════════════════════════════════════════════════════════
@export_group("Points de flottaison")
@export var float_points: Array[Vector3] = [
	Vector3(-3.0, 0.0,  1.5),
	Vector3( 3.0, 0.0,  1.5),
	Vector3(-3.0, 0.0, -1.5),
	Vector3( 3.0, 0.0, -1.5),
	Vector3( 0.0, 0.0,  2.5),
	Vector3( 0.0, 0.0, -2.5),
]
@export_range(-5.0, 5.0, 0.05) var point_y_offset: float = 0.0

@export_group("Eau")
@export var sea_node: MeshInstance3D

@export_group("Flottaison")
@export_range(0.0, 5000.0,  1.0) var buoyancy_force:       float = 80.0
@export_range(0.0, 10000.0, 5.0) var max_buoyancy_force:   float = 200.0
@export_range(0.0,  20.0,  0.1)  var water_damping:         float = 4.0
@export_range(0.0,  10.0,  0.1)  var angular_damping_water: float = 2.0
@export_range(0.0, 1.0, 0.05) var min_water_control: float = 0.15

@export_group("Vol")
@export var target_marker: MeshInstance3D
@export var forward_is_plus_z: bool = true
@export_range(0.0, 100000.0, 100.0) var thrust_force: float = 8000.0

@export_group("Physique de vol")
@export var turn_torque: Vector3 = Vector3(90.0, 25.0, 45.0)
@export_range(0.0, 10000.0, 10.0) var force_mult:             float = 1000.0
@export_range(0.0, 10.0, 0.1)     var angular_damping_flight: float = 2.0
@export_range(1.0, 200.0, 1.0)    var torque_full_speed:      float = 50.0
@export_range(0.05, 2.0, 0.05) var throttle_change_rate: float = 0.5
@export var throttle_label: Label

@export_group("Autopilote")
@export_range(0.1, 20.0, 0.1) var sensitivity:           float = 5.0
@export_range(1.0, 90.0, 1.0) var aggressive_turn_angle: float = 10.0
@export_range(0.0, 1.0, 0.05) var max_roll:              float = 0.5
@export_range(0.0, 30.0, 0.5) var min_angle_for_roll:    float = 5.0
@export_range(1.0, 10.0, 0.5) var aligned_damping_mult:  float = 5.0

@export_group("Surfaces de contrôle")
## Aileron gauche  — roulis (axe Z local)
@export var aileron_left:  Node3D
## Aileron droit   — roulis (axe Z local, opposition)
@export var aileron_right: Node3D
## Gouverne de profondeur — tangage (axe X local)
@export var elevator:      Node3D
## Gouverne de direction  — lacet   (axe Y local)
@export var rudder:        Node3D
## Débattement maximum des surfaces (degrés)
@export_range(0.0, 45.0, 0.5) var surface_max_deg: float = 25.0
## Vitesse de lissage de la rotation des surfaces
@export_range(1.0, 30.0, 0.5) var surface_smooth:  float = 10.0

@export_group("Aerodynamique")
@export_range(0.0, 100000.0, 100.0) var lift_max:       float = 5000.0
@export_range(1.0, 200.0, 1.0)      var lift_full_speed: float = 30.0
@export_range(1.0, 45.0, 0.5)       var aoa_max_deg:    float = 15.0
@export_range(0.0, 5000.0, 10.0)    var lateral_drag:   float = 800.0

# ═══════════════════════════════════════════════════════════════════════════════
# EFFETS DE VITESSE EXTRÊME
# ═══════════════════════════════════════════════════════════════════════════════
@export_group("Effets de vitesse")
## Mesh principal de l'avion (le node visuel sur lequel appliquer le tremblement).
## Doit être un enfant direct du RigidBody3D avec rotation locale nulle au repos.
@export var airplane_mesh: Node3D

## Vitesse (km/h) à partir de laquelle le tremblement commence
@export_range(0.0, 500.0, 10.0) var shake_speed_start:    float = 300.0
## Vitesse (km/h) à laquelle le tremblement atteint son intensité maximale
@export_range(0.0, 800.0, 10.0) var shake_speed_max:      float = 500.0
## Intensité maximale du tremblement sur les axes X et Z (en radians)
@export_range(0.0, 0.1, 0.001)  var shake_intensity_max:  float = 0.012
## Intensité maximale du tremblement sur l'axe Y (lacet), proportionnelle à X/Z
@export_range(0.0, 1.0, 0.05)   var shake_yaw_ratio:      float = 0.25

## Vitesse (km/h) à partir de laquelle les roulis oscillants démarrent
@export_range(0.0, 600.0, 10.0) var roll_osc_speed_start: float = 350.0
## Vitesse (km/h) sur laquelle la rampe des roulis oscillants monte (0 → plein)
@export_range(10.0, 200.0, 10.0) var roll_osc_ramp_range: float = 50.0
## Amplitude des roulis oscillants (multiplicateur appliqué à force_mult)
@export_range(0.0, 10.0, 0.05)   var roll_osc_amplitude:   float = 0.8
## Fréquence des roulis oscillants (Hz) — plus c'est élevé, plus c'est rapide
@export_range(0.1, 10.0, 0.1)   var roll_osc_frequency:   float = 2.5

@export_group("Shader / Vagues")
@export_range(0.0, 5.0, 0.01)  var height_scale:      float   = 0.5
@export_range(0.0, 5.0, 0.01)  var noise_scale:       float   = 1.0
@export                         var noise_offset:      Vector2 = Vector2.ZERO
@export_range(0.0, 5.0, 0.01)  var speed:             float   = 0.5
## 0 = FBM  |  1 = sinus
@export_range(0.0, 1.0, 1.0)   var wave_mode:         float   = 0.0
@export_range(0.0, 1.0, 0.01)  var fbm_smooth_amount: float   = 0.4
@export_range(0.0, 2.0, 0.01)  var wave2_strength:    float   = 0.7
@export_range(-5.0, 5.0, 0.01) var calm_water_height: float   = 0.5

@export_group("Shader / Vagues sinusoïdales")
@export_range(0.0, 10.0, 0.01) var sin_freq1: float   = 1.0
@export_range(0.0, 2.0, 0.01)  var sin_amp1:  float   = 0.35
@export                         var sin_dir1:  Vector2 = Vector2(1.0, 0.0)
@export_range(0.0, 10.0, 0.01) var sin_freq2: float   = 2.0
@export_range(0.0, 2.0, 0.01)  var sin_amp2:  float   = 0.12
@export                         var sin_dir2:  Vector2 = Vector2(0.6, 0.8)
@export_range(0.0, 10.0, 0.01) var sin_freq3: float   = 0.5
@export_range(0.0, 2.0, 0.01)  var sin_amp3:  float   = 0.25

@export_group("Shader / Îles")
@export                         var island_count: int = 4
## Chaque Vector4 = (pos_x, pos_z, calm_radius, shore_radius).
@export var islands: Array[Vector4] = [
	Vector4(0.0, 0.0, 30.0, 80.0),
	Vector4(200.0, -150.0, 25.0, 60.0),
]

@export_group("Sortie")
## Position locale où le personnage est téléporté quand il sort de l'avion.
@export var exit_point: Vector3 = Vector3(4.0, 1.0, 0.0)

@export_group("Debug")
@export var show_debug_spheres: bool = true
@export var print_raw_pixels:   bool = false
@export var print_depths:       bool = false

@export_group("Audio")
@export var airplane_listener: AudioListener3D
@export var player_listener:   AudioListener3D

# ═══════════════════════════════════════════════════════════════════════════════
# ENCODAGE (hauteur eau → RGB 24 bits)
# ═══════════════════════════════════════════════════════════════════════════════
const HEIGHT_MIN:   float = -10.0
const HEIGHT_RANGE: float =  60.0

# ═══════════════════════════════════════════════════════════════════════════════
# QUERY SHADER
# ═══════════════════════════════════════════════════════════════════════════════
const _QUERY_SHADER := """
shader_type canvas_item;

uniform vec2  query_points[8];
uniform int   query_count = 6;

uniform float height_scale      = 0.5;
uniform float noise_scale       = 1.0;
uniform vec2  noise_offset      = vec2(0.0);
uniform float speed             = 0.5;
uniform float wave_mode         = 0.0;
uniform float fbm_smooth_amount = 0.4;
uniform float wave2_strength    = 0.7;
uniform float calm_water_height = 0.5;
uniform float sin_freq1 = 1.0;
uniform float sin_amp1  = 0.35;
uniform vec2  sin_dir1  = vec2(1.0, 0.0);
uniform float sin_freq2 = 2.0;
uniform float sin_amp2  = 0.12;
uniform vec2  sin_dir2  = vec2(0.6, 0.8);
uniform float sin_freq3 = 0.5;
uniform float sin_amp3  = 0.25;
uniform vec4  islands[32];
uniform int   island_count  = 4;
uniform float water_base_y  = 0.0;
uniform float water_scale_y = 1.0;
uniform vec2  player_xz     = vec2(0.0);
uniform float height_min    = -10.0;
uniform float height_range  =  60.0;

const float COS_0   =  1.0;  const float SIN_0   =  0.0;
const float COS_120 = -0.5;  const float SIN_120 =  0.8660254;
const float COS_240 = -0.5;  const float SIN_240 = -0.8660254;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float vnoise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    float a = hash(i); float b = hash(i + vec2(1.0,0.0));
    float c = hash(i + vec2(0.0,1.0)); float d = hash(i + vec2(1.0,1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a,b,u.x) + (c-a)*u.y*(1.0-u.x) + (d-b)*u.x*u.y;
}
float fbm(vec2 x) {
    float h=0.0, amp=0.5, freq=1.0;
    for (int i=0;i<5;i++) { h+=vnoise(x*freq)*amp; amp*=0.5; freq*=2.0; }
    return h;
}
float fbm_at(vec2 xz, vec2 drift) {
    return fbm(xz * noise_scale + noise_offset + drift * (TIME * speed));
}
float fbm_smooth_dir(vec2 xz, float ca, float sa, vec2 drift) {
    vec2 r = vec2(ca*xz.x - sa*xz.y, sa*xz.x + ca*xz.y);
    float s  = fbm_at(r, drift);
    float o1 = fbm_at(r + vec2( fbm_smooth_amount, 0.0), drift);
    float o2 = fbm_at(r + vec2(-fbm_smooth_amount, 0.0), drift);
    float o3 = fbm_at(r + vec2(0.0,  fbm_smooth_amount), drift);
    float o4 = fbm_at(r + vec2(0.0, -fbm_smooth_amount), drift);
    return (s + o1 + o2 + o3 + o4) * 0.2;
}
float sin_waves(vec2 xz) {
    vec2 d1 = normalize(sin_dir1);
    vec2 d2 = normalize(sin_dir2);
    vec2 d3 = normalize(sin_dir2.yx * vec2(-1.0, 1.0));
    float t = TIME * speed;
    return sin(dot(xz,d1)*sin_freq1+t)*sin_amp1
         + sin(dot(xz,d2)*sin_freq2+t)*sin_amp2
         + sin(dot(xz,d3)*sin_freq3+t)*sin_amp3;
}
float get_calm_factor(vec2 pos_abs) {
    float calm = 1.0;
    for (int i = 0; i < 32; i++) {
        if (i >= island_count) break;
        float dist = length(pos_abs - islands[i].xy);
        calm = min(calm, smoothstep(islands[i].w, islands[i].z, dist));
    }
    return calm;
}

void fragment() {
    int idx = clamp(int(UV.x * float(query_count)), 0, query_count - 1);
    vec2 abs_xz = query_points[idx];
    vec2 rel_xz = abs_xz - player_xz;

    float h = 0.0;
    if (wave_mode < 0.5) {
        float h1 = fbm_smooth_dir(rel_xz, COS_0,   SIN_0,   vec2( 0.8,  0.3));
        float h2 = fbm_smooth_dir(rel_xz, COS_120, SIN_120, vec2(-0.8,  0.3)) * wave2_strength;
        float h3 = fbm_smooth_dir(rel_xz, COS_240, SIN_240, vec2( 0.8, -0.3)) * wave2_strength;
        h = (h1 + h2 + h3) * 0.3333;
    } else {
        h = sin_waves(rel_xz);
    }
    float calm   = get_calm_factor(abs_xz);
    float model_y = mix(calm_water_height, h * height_scale, calm);
    float world_y = water_base_y + model_y * water_scale_y;

    float n  = clamp((world_y - height_min) / height_range, 0.0, 1.0);
    float ns = n * 255.0 * 255.0 * 255.0;
    float r  = floor(ns / (255.0 * 255.0));
    float g  = floor(mod(ns, 255.0 * 255.0) / 255.0);
    float b  = mod(ns, 255.0);
    COLOR = vec4(r / 255.0, g / 255.0, b / 255.0, 1.0);
}
"""

# ═══════════════════════════════════════════════════════════════════════════════
# ETAT INTERNE
# ═══════════════════════════════════════════════════════════════════════════════
var _sea_mat:         ShaderMaterial
var _water_base_y:    float                 = 0.0
var _water_scale_y:   float                 = 1.0
var _viewport:        SubViewport
var _query_mat:       ShaderMaterial
var _surface_heights: Array[float]          = []
var _submerged_count: int                   = 0
var _debug_meshes:    Array[MeshInstance3D] = []
var _print_timer:     float                 = 0.0
var _ready_ok:        bool                  = false

## Mis a true par le script du joueur lors de l'embarquement
var occupied: bool = false

# ── Audio ────────────────────────────────────────────────────────────────────
var _prev_occupied: bool = false
@onready var _engine_audio: Node = $EngineAudioManager

# ── Délai de poussée à l'embarquement ────────────────────────────────────────
## Temps restant avant que la poussée (KEY_Z) soit autorisée après embarquement.
var _boarding_thrust_timer: float = 0.0
const BOARDING_THRUST_DELAY: float = 1.0
var _throttle: float = 0.0

# ── Rotations cibles des surfaces de contrôle (degrés) ───────────────────────
var _surf_pitch: float = 0.0   # elevator   → rotation X
var _surf_yaw:   float = 0.0   # rudder     → rotation Y
var _surf_roll:  float = 0.0   # ailerons   → rotation Z (± opposition)

# ── Effets de vitesse ─────────────────────────────────────────────────────────
## Rotation de repos du mesh (mémorisée en _ready pour ne pas la corrompre)
var _mesh_base_rot:  Vector3 = Vector3.ZERO
## Accumulateur de temps pour les roulis oscillants (ne se remet jamais à 0)
var _roll_osc_time:  float   = 0.0

# ═══════════════════════════════════════════════════════════════════════════════
# INITIALISATION
# ═══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	if not sea_node:
		push_error("[Buoyancy] sea_node non assigne !")
		return
	_sea_mat = sea_node.get_active_material(0) as ShaderMaterial
	if not _sea_mat:
		push_error("[Buoyancy] Pas de ShaderMaterial sur sea_node !")
		return
	_water_base_y  = sea_node.global_position.y
	_water_scale_y = sea_node.global_transform.basis.get_scale().y
	_surface_heights.resize(float_points.size())
	for i in range(float_points.size()):
		_surface_heights[i] = _water_base_y
	_setup_viewport()
	_build_debug_spheres()

	# ── Mémorise la rotation de repos du mesh principal ───────────────────────
	if airplane_mesh:
		_mesh_base_rot = airplane_mesh.rotation
	else:
		push_warning("[Buoyancy] airplane_mesh non assigné — le tremblement ne sera pas visible.")

	_ready_ok = true


func _setup_viewport() -> void:
	var count: int = float_points.size()

	var shader: Shader = Shader.new()
	shader.code = _QUERY_SHADER
	_query_mat = ShaderMaterial.new()
	_query_mat.shader = shader

	_viewport = SubViewport.new()
	_viewport.size                       = Vector2i(count, 1)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d                 = true
	_viewport.transparent_bg             = false
	add_child(_viewport)

	var cr: ColorRect = ColorRect.new()
	cr.size     = Vector2(count, 1)
	cr.material = _query_mat
	_viewport.add_child(cr)

	_query_mat.set_shader_parameter("height_scale",      height_scale)
	_query_mat.set_shader_parameter("noise_scale",       noise_scale)
	_query_mat.set_shader_parameter("noise_offset",      noise_offset)
	_query_mat.set_shader_parameter("speed",             speed)
	_query_mat.set_shader_parameter("wave_mode",         wave_mode)
	_query_mat.set_shader_parameter("fbm_smooth_amount", fbm_smooth_amount)
	_query_mat.set_shader_parameter("wave2_strength",    wave2_strength)
	_query_mat.set_shader_parameter("calm_water_height", calm_water_height)
	_query_mat.set_shader_parameter("sin_freq1",         sin_freq1)
	_query_mat.set_shader_parameter("sin_amp1",          sin_amp1)
	_query_mat.set_shader_parameter("sin_dir1",          sin_dir1)
	_query_mat.set_shader_parameter("sin_freq2",         sin_freq2)
	_query_mat.set_shader_parameter("sin_amp2",          sin_amp2)
	_query_mat.set_shader_parameter("sin_dir2",          sin_dir2)
	_query_mat.set_shader_parameter("sin_freq3",         sin_freq3)
	_query_mat.set_shader_parameter("sin_amp3",          sin_amp3)
	_query_mat.set_shader_parameter("water_base_y",      _water_base_y)
	_query_mat.set_shader_parameter("water_scale_y",     _water_scale_y)
	_query_mat.set_shader_parameter("height_min",        HEIGHT_MIN)
	_query_mat.set_shader_parameter("height_range",      HEIGHT_RANGE)
	_query_mat.set_shader_parameter("query_count",       count)
	_apply_islands_to_query_mat()

func _apply_islands_to_query_mat() -> void:
	var padded: Array[Vector4] = []
	padded.resize(32)
	var count: int = mini(islands.size(), 32)
	for i in range(32):
		padded[i] = islands[i] if i < count else Vector4.ZERO
	_query_mat.set_shader_parameter("islands",      padded)
	_query_mat.set_shader_parameter("island_count", island_count)

# ═══════════════════════════════════════════════════════════════════════════════
# DECODE RGB 24 bits → float
# ═══════════════════════════════════════════════════════════════════════════════
func _decode(c: Color) -> float:
	var r: float = round(c.r * 255.0)
	var g: float = round(c.g * 255.0)
	var b: float = round(c.b * 255.0)
	var n: float = (r * 255.0 * 255.0 + g * 255.0 + b) / (255.0 * 255.0 * 255.0)
	return HEIGHT_MIN + n * HEIGHT_RANGE

# ═══════════════════════════════════════════════════════════════════════════════
# EFFETS VISUELS — TREMBLEMENT (frame visuel, pas physique)
# ═══════════════════════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	if not airplane_mesh or not _ready_ok:
		return

	var spd_kmh: float = linear_velocity.length() * 3.6

	# Rampe 0 → 1 entre shake_speed_start et shake_speed_max
	var shake_t: float = clampf(
		(spd_kmh - shake_speed_start) / maxf(shake_speed_max - shake_speed_start, 1.0),
		0.0, 1.0
	)

	if shake_t > 0.0:
		var i: float = shake_t * shake_intensity_max
		# Bruit aléatoire par frame sur X, Y (réduit), Z → effet "turbulences"
		airplane_mesh.rotation = _mesh_base_rot + Vector3(
			randf_range(-i, i),
			randf_range(-i * shake_yaw_ratio, i * shake_yaw_ratio),
			randf_range(-i, i)
		)
	else:
		# Retour propre à la rotation de repos
		airplane_mesh.rotation = _mesh_base_rot

# ═══════════════════════════════════════════════════════════════════════════════
# BOUCLE PHYSIQUE
# ═══════════════════════════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if not _ready_ok:
		return
	_update_query()
	_read_results()
	_submerged_count = 0
	_apply_buoyancy()
	_apply_water_drag(delta)
	_apply_flight_control(delta)
	if print_depths or print_raw_pixels:
		_print_timer += delta
		if _print_timer >= 1.0:
			_print_timer = 0.0
			if print_depths:
				var wp0: Vector3 = to_global(float_points[0])
				print("[Buoyancy] surf[0]=", snappedf(_surface_heights[0], 0.01),
					  " pt[0].y=", snappedf(wp0.y, 0.01),
					  " depth=", snappedf(_surface_heights[0] - wp0.y, 0.01),
					  " base_y=", _water_base_y)

	# ── Décompte du délai de poussée post-embarquement ────────────────────────
	if _boarding_thrust_timer > 0.0:
		_boarding_thrust_timer -= delta

	# ── Suivi de l'état occupied + audio ─────────────────────────────────────
	if occupied != _prev_occupied:
		if occupied:
			_throttle = 0.0
			_boarding_thrust_timer = BOARDING_THRUST_DELAY  # démarre le délai
			_engine_audio.start_engine()
			if airplane_listener:
				airplane_listener.make_current()
		else:
			_engine_audio.stop_engine()
			if player_listener:
				player_listener.make_current()
		_prev_occupied = occupied

	if occupied:
		if Input.is_key_pressed(KEY_Z):
			_throttle = minf(_throttle + throttle_change_rate * delta, 1.0)
		elif Input.is_key_pressed(KEY_S):
			_throttle = maxf(_throttle - throttle_change_rate * delta, 0.0)
		_engine_audio.set_throttle(_throttle)
		if throttle_label:
			throttle_label.text = "Gaz : %d %%" % roundi(_throttle * 100.0)

	_engine_audio.audio_process(delta)

# ── Retourne la position monde où doit apparaître le joueur à la sortie ───────
func get_exit_world_position() -> Vector3:
	return to_global(exit_point)


func _update_query() -> void:
	if _sea_mat:
		var pxz = _sea_mat.get_shader_parameter("player_xz")
		if pxz != null:
			_query_mat.set_shader_parameter("player_xz", Vector2(pxz))
	var arr: Array = []
	for i in range(8):
		if i < float_points.size():
			var lp: Vector3 = float_points[i] + Vector3(0.0, point_y_offset, 0.0)
			var wp: Vector3 = to_global(lp)
			arr.append(Vector2(wp.x, wp.z))
		else:
			arr.append(Vector2.ZERO)
	_query_mat.set_shader_parameter("query_points", arr)

func _read_results() -> void:
	var tex: ViewportTexture = _viewport.get_texture()
	if not tex:
		push_warning("[Buoyancy] viewport texture null")
		return
	var img: Image = tex.get_image()
	if not img:
		push_warning("[Buoyancy] get_image() null")
		return
	for i in range(float_points.size()):
		var c: Color = img.get_pixel(i, 0)
		if print_raw_pixels and _print_timer <= 0.0:
			print("[Buoyancy] pixel[",i,"] r=",snappedf(c.r,0.001),
				  " g=",snappedf(c.g,0.001)," b=",snappedf(c.b,0.001),
				  " → h=",snappedf(_decode(c),0.01))
		_surface_heights[i] = _decode(c)

# ═══════════════════════════════════════════════════════════════════════════════
# FLOTTAISON
# ═══════════════════════════════════════════════════════════════════════════════
func _apply_buoyancy() -> void:
	for i in range(float_points.size()):
		var lp: Vector3  = float_points[i] + Vector3(0.0, point_y_offset, 0.0)
		var wp: Vector3  = to_global(lp)
		var surf: float  = _surface_heights[i]
		var depth: float = surf - wp.y
		if show_debug_spheres and i < _debug_meshes.size():
			_debug_meshes[i].global_position = wp
			var mat := _debug_meshes[i].material_override as StandardMaterial3D
			mat.albedo_color = Color(0.1, 0.8, 0.1) if depth <= 0.0 else Color(0.1, 0.3, 1.0)
		if depth <= 0.0:
			continue
		_submerged_count += 1
		var up:  float = clampf(depth * buoyancy_force, 0.0, max_buoyancy_force)
		var dmp: float = -linear_velocity.dot(transform.basis.y) * water_damping
		apply_force(Vector3(0.0, up + dmp, 0.0), wp - global_position)

func _apply_water_drag(delta: float) -> void:
	if _submerged_count == 0:
		return
	var ratio: float = float(_submerged_count) / float(float_points.size())
	angular_velocity -= angular_velocity * angular_damping_water * ratio * delta

# ═══════════════════════════════════════════════════════════════════════════════
# VOL
# ═══════════════════════════════════════════════════════════════════════════════
func _apply_flight_control(delta: float) -> void:
	var forward: Vector3 = global_basis.z if forward_is_plus_z else -global_basis.z

	# ── Accumulateur de temps pour les oscillations (toujours actif) ──────────
	_roll_osc_time += delta

	if _submerged_count == 0:
		var spd:     float = linear_velocity.length()
		var spd_kmh: float = spd * 3.6

		# ── Lift : rampe progressive 0 → lift_max entre 0 et lift_full_speed ──
		var lift_speed_t: float = clampf(spd / lift_full_speed, 0.0, 1.0)
		var local_vel: Vector3  = global_basis.inverse() * linear_velocity
		var aoa_rad: float      = atan2(-local_vel.y, maxf(local_vel.z, 0.001))
		if aoa_rad > 0.0:
			var aoa_t:  float = clampf(aoa_rad / deg_to_rad(aoa_max_deg), 0.0, 1.0)
			var nose_t: float = clampf(1.0 + forward.y, 0.0, 1.0)
			apply_central_force(global_basis.y * lift_speed_t * aoa_t * nose_t * lift_max)

		# ── Drag latéral ────────────────────────────────────────────────────
		var lateral_vel: float = linear_velocity.dot(global_basis.x)
		apply_central_force(-global_basis.x * lateral_vel * lateral_drag)

		# ── Roulis oscillants haute vitesse ───────────────────────────────────
		# Rampe douce de 0 à 1 sur roll_osc_ramp_range km/h au-dessus du seuil
		var osc_t: float = clampf(
			(spd_kmh - roll_osc_speed_start) / maxf(roll_osc_ramp_range, 1.0),
			0.0, 1.0
		)
		if osc_t > 0.0:
			# Sinusoïde pure → roulis gauche/droite réguliers
			var osc: float      = sin(_roll_osc_time * roll_osc_frequency * TAU)
			var roll_sign: float = 1.0 if forward_is_plus_z else -1.0
			apply_torque(
				global_basis
				* Vector3(0.0, 0.0, osc * roll_osc_amplitude * osc_t * roll_sign)
				* force_mult
			)

	# ── Poussée : bloquée pendant le délai d'embarquement ───────────────────
	if occupied and _boarding_thrust_timer <= 0.0 and _throttle > 0.0:
		apply_central_force(forward * thrust_force * _throttle)

	# APRÈS
	if not target_marker:
		return

	# Ratio de contrôle : 1.0 en vol, réduit sur l'eau
	var water_ratio: float = lerpf(min_water_control, 1.0,
	1.0 - float(_submerged_count) / float(float_points.size()))

	# ── Couple multiplieur : rampe progressive 0 → force_mult ───────────────
	var speed_t: float = clampf(linear_velocity.length() / (torque_full_speed*4), 0.0, 1.0)
	_run_autopilot(forward, speed_t * water_ratio, delta)

func _run_autopilot(forward: Vector3, speed_t: float, delta: float) -> void:
	var fly_target: Vector3 = target_marker.global_position
	var to_target:  Vector3 = fly_target - global_position
	if to_target.is_zero_approx():
		return

	var desired_dir:   Vector3 = to_target.normalized()
	var angle_off_deg: float   = rad_to_deg(forward.angle_to(desired_dir))

	# ── Lacet / Tangage ──────────────────────────────────────────────────────
	var steer_world: Vector3 = forward.cross(desired_dir)
	var steer_local: Vector3 = global_basis.inverse() * steer_world

	var steer_torque: Vector3 = Vector3(
		steer_local.x * sensitivity * turn_torque.x,
		steer_local.y * sensitivity * turn_torque.y,
		0.0
	) * force_mult * speed_t

	if not forward_is_plus_z:
		steer_torque.x = -steer_torque.x
		steer_torque.y = -steer_torque.y

	apply_torque(global_basis * steer_torque)

	# ── Roulis ───────────────────────────────────────────────────────────────
	var roll_range: float = maxf(aggressive_turn_angle - min_angle_for_roll, 0.1)
	var roll_blend: float = clampf(
		(angle_off_deg - min_angle_for_roll) / roll_range,
		0.0, 1.0
	)

	var local_target_dir: Vector3 = to_local(fly_target).normalized()
	var aggressive_roll:  float   = local_target_dir.x * sensitivity
	if not forward_is_plus_z:
		aggressive_roll = -aggressive_roll

	var wings_level_roll: float = global_basis.x.y
	var roll_input: float = clampf(
		lerpf(wings_level_roll, aggressive_roll, roll_blend),
		-max_roll, max_roll
	)

	var roll_sign: float = 1.0 if forward_is_plus_z else -1.0
	apply_torque(
		global_basis
		* Vector3(0.0, 0.0, -turn_torque.z * roll_input * roll_sign)
		* force_mult * speed_t
	)

	# ── Damping adaptatif ────────────────────────────────────────────────────
	var align_t: float = 1.0 - clampf(angle_off_deg / aggressive_turn_angle, 0.0, 1.0)
	var effective_damping: float = lerpf(
		angular_damping_flight,
		angular_damping_flight * aligned_damping_mult,
		align_t
	)
	angular_velocity -= angular_velocity * effective_damping * speed_t * delta

	# ── Surfaces de contrôle visuelles ───────────────────────────────────────
	# Inputs normalisés −1..1 extraits des mêmes valeurs que les couples
	var pitch_norm: float = clampf(steer_local.x * sensitivity, -1.0, 1.0)
	var yaw_norm:   float = clampf(steer_local.y * sensitivity, -1.0, 1.0)
	var roll_norm:  float = clampf(roll_input    / maxf(max_roll, 0.001), -1.0, 1.0)

	# Cibles en degrés
	var target_pitch: float = pitch_norm * surface_max_deg
	var target_yaw:   float = yaw_norm   * surface_max_deg
	var target_roll:  float = roll_norm  * surface_max_deg

	# Lissage
	_surf_pitch = lerpf(_surf_pitch, target_pitch, surface_smooth * delta)
	_surf_yaw   = lerpf(_surf_yaw,   target_yaw,   surface_smooth * delta)
	_surf_roll  = lerpf(_surf_roll,  target_roll,  surface_smooth * delta)

	# Application sur les nodes (rotation locale)
	if elevator:
		elevator.rotation_degrees.x      = -_surf_pitch        # ← signe inversé
	if rudder:
		rudder.rotation_degrees.y        = -_surf_yaw          # ← signe inversé
	if aileron_left:
		aileron_left.rotation_degrees.x  =  -_surf_roll         # ← axe X (comme elevator)
	if aileron_right:
		aileron_right.rotation_degrees.x = _surf_roll

# ═══════════════════════════════════════════════════════════════════════════════
# DEBUG SPHERES
# ═══════════════════════════════════════════════════════════════════════════════
func _build_debug_spheres() -> void:
	for m in _debug_meshes:
		m.queue_free()
	_debug_meshes.clear()
	if not show_debug_spheres:
		return
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.30
	for _p in float_points:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color  = Color(0.1, 0.8, 0.1)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh              = sm
		mi.material_override = mat
		add_child(mi)
		_debug_meshes.append(mi)
