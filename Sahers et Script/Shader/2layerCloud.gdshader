// CloudLayer2D.gdshader
// Couche de nuages 2D pour un plane en altitude.
// Utilise du FBM pour la forme et anime les nuages avec le vent.

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────
//  PARAMÈTRES
// ─────────────────────────────────────────────

group_uniforms Forme;
/// Échelle des nuages. Plus grand = nuages plus petits.
uniform float cloud_scale        : hint_range(0.1, 5.0)  = 1.0;
/// Seuil d'apparition. Monte pour moins de nuages, descends pour plus.
uniform float cloud_threshold    : hint_range(0.0, 1.0)  = 0.45;
/// Douceur des bords (0 = net, 1 = très doux).
uniform float cloud_softness     : hint_range(0.01, 0.5) = 0.15;
/// Opacité maximale des nuages.
uniform float cloud_opacity      : hint_range(0.0, 1.0)  = 0.85;

group_uniforms Detail;
uniform float detail_scale  : hint_range(1.0, 10.0) = 4.0;
uniform float detail_weight : hint_range(0.0, 1.0)  = 0.25;

group_uniforms Vent;
uniform vec2  wind_direction = vec2(1.0, 0.3);
uniform float wind_speed     : hint_range(0.0, 50.0) = 4.0;
/// Le détail se déplace légèrement plus vite (turbulence).
uniform float wind_detail_factor : hint_range(0.5, 3.0) = 1.5;

group_uniforms Couleurs;
uniform vec4 color_light : source_color = vec4(1.0,  1.0,  1.0,  1.0);
uniform vec4 color_dark  : source_color = vec4(0.75, 0.80, 0.88, 1.0);
/// Illumination par le bas (simule lumière réfléchie par la mer).
uniform vec4 color_bottom : source_color = vec4(0.85, 0.90, 1.0, 1.0);
/// Mélange bas/haut selon la normale de vue (0 = uniquement haut).
uniform float bottom_light : hint_range(0.0, 1.0) = 0.3;

group_uniforms Fondu;
/// Fondu sur les bords du plane pour éviter les coupures visibles.
uniform float edge_fade : hint_range(0.0, 0.5) = 0.15;

group_uniforms Courbure;
/// Rayon de courbure de la lentille en unités monde.
/// Plus petit = plus courbé. Ex: 10000 = très légère courbure, 2000 = prononcée.
uniform float earth_radius : hint_range(20.0, 50000.0) = 8000.0;

// ─────────────────────────────────────────────
//  VARYING
// ─────────────────────────────────────────────

varying vec3 v_world_pos;
varying vec2 v_world_xz;

void vertex() {
	// Position monde AVANT courbure
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Distance horizontale depuis le centre du plane (en world space)
	vec2  offset_xz = world_pos.xz - MODEL_MATRIX[3].xz;
	float dist2     = dot(offset_xz, offset_xz);

	// Courbure sphérique : y = -dist² / (2 * R)
	// Simule la courbure de la Terre vue de loin
	float curve_y = -(dist2) / (2.0 * earth_radius * earth_radius);

	// Applique la courbure en local Y
	VERTEX.y += curve_y;

	// Recalcule la position monde avec la courbure pour le fragment
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz  = world_pos.xz;
}

// ─────────────────────────────────────────────
//  NOISE
// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
//  SIMPLEX NOISE 2D — zéro artefact en grille
// ─────────────────────────────────────────────

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)),
	         dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float snoise(vec2 p) {
	const float K1 = 0.366025404; // (sqrt(3)-1)/2
	const float K2 = 0.211324865; // (3-sqrt(3))/6

	vec2 i = floor(p + (p.x + p.y) * K1);
	vec2 a = p - i + (i.x + i.y) * K2;
	float m = step(a.y, a.x);
	vec2 o = vec2(m, 1.0 - m);
	vec2 b = a - o + K2;
	vec2 c = a - 1.0 + 2.0 * K2;

	vec3 h = max(0.5 - vec3(dot(a,a), dot(b,b), dot(c,c)), 0.0);
	vec3 n = h * h * h * h * vec3(
		dot(a, hash2(i)),
		dot(b, hash2(i + o)),
		dot(c, hash2(i + 1.0))
	);
	return dot(n, vec3(70.0)) * 0.5 + 0.5;
}

float fbm(vec2 p) {
	float v = 0.0;
	v += snoise(p)         * 0.500;
	v += snoise(p * 2.13)  * 0.250;
	v += snoise(p * 4.31)  * 0.125;
	v += snoise(p * 8.57)  * 0.063;
	v += snoise(p * 17.13) * 0.031;
	return clamp(v / 0.969, 0.0, 1.0);
}

float fbm_warped(vec2 p) {
	vec2 warp = vec2(
		fbm(p + vec2(1.7, 9.2)),
		fbm(p + vec2(8.3, 2.8))
	) * 0.6;
	return fbm(p + warp);
}

// ─────────────────────────────────────────────
//  FRAGMENT
// ─────────────────────────────────────────────

void fragment() {
	const float WORLD_SCALE = 1.0 / 3000.0;
	vec2 wind_offset = normalize(wind_direction) * wind_speed * TIME * WORLD_SCALE;
	vec2 noise_pos   = v_world_xz * WORLD_SCALE * cloud_scale + wind_offset;

	// ---- Forme principale (domain warped pour plus d'organicité) ----
	float shape = fbm_warped(noise_pos);

	// ---- Détail (érosion des bords) ----
	vec2  detail_pos = noise_pos * detail_scale + wind_offset * wind_detail_factor;
	float detail     = snoise(detail_pos) * 0.6 + snoise(detail_pos * 2.1) * 0.4;
	float erode      = pow(1.0 - clamp(shape, 0.0, 1.0), 2.0);
	float density    = shape - (1.0 - detail) * erode * detail_weight;

	// ---- Masque de nuage ----
	float cloud_mask = smoothstep(
		cloud_threshold,
		cloud_threshold + cloud_softness,
		density
	);

	// ---- Forme lentille : distance elliptique depuis le centre ----
	vec2  uv_centered = (UV - 0.5) * 2.0;  // [-1, 1] sur chaque axe
	float lens_dist   = length(uv_centered);  // distance circulaire depuis le centre
	float edge = 1.0 - smoothstep(1.0 - edge_fade, 1.0, lens_dist);
	cloud_mask *= edge;

	// ---- Couleur haut/bas selon angle de vue ----
	float view_bottom = clamp(VIEW.y, 0.0, 1.0);
	vec3  cloud_color = mix(
		mix(color_dark.rgb, color_light.rgb, clamp(density * 1.5, 0.0, 1.0)),
		color_bottom.rgb,
		view_bottom * bottom_light
	);

	ALBEDO = cloud_color;
	ALPHA  = cloud_mask * cloud_opacity;
}
