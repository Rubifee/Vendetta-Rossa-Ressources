// CloudVolume.gdshader
// Ray marching volumétrique optimisé — Value Noise au lieu de Worley.

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

// ─────────────────────────────────────────────
//  PARAMÈTRES
// ─────────────────────────────────────────────

group_uniforms Forme;
/// Échelle du bruit. Plus grand = structures plus petites dans la boîte.
uniform float cloud_scale        : hint_range(0.1, 10.0) = 2.0;
/// Monte density_offset pour avoir plus de nuage (0.5 est un bon départ).
uniform float density_offset     : hint_range(0.0, 3.0)  = 0.5;
/// Multiplicateur final.
uniform float density_multiplier : hint_range(0.0, 5.0)  = 2.0;
uniform float bottom_fade : hint_range(0.0, 0.5) = 0.2;  // fondu bas
uniform float top_fade    : hint_range(0.5, 1.0) = 0.65; // fondu haut

group_uniforms Detail;
uniform float detail_scale  : hint_range(1.0, 20.0) = 3.0;
uniform float detail_weight : hint_range(0.0, 1.0)  = 0.3;

group_uniforms Vent;
/// Direction du vent sur le plan horizontal (X = Est/Ouest, Z = Nord/Sud).
uniform vec3  wind_direction = vec3(1.0, 0.0, 0.3);
/// Vitesse du vent en unités monde / seconde.
uniform float wind_speed : hint_range(0.0, 50.0) = 5.0;
/// Le détail se déplace légèrement plus vite que la forme (turbulence).
uniform float wind_detail_factor : hint_range(0.5, 3.0) = 1.4;

group_uniforms Lumiere;
uniform vec3  light_dir                                    = vec3(0.3, 0.8, 0.3);
uniform vec4  light_color : source_color                   = vec4(1.0, 0.96, 0.88, 1.0);
uniform float light_absorption_cloud : hint_range(0.0, 5.0) = 1.0;
uniform float light_absorption_sun   : hint_range(0.0, 5.0) = 0.8;
uniform float darkness_threshold     : hint_range(0.0, 1.0) = 0.1;
uniform float forward_scatter        : hint_range(0.0, 1.0) = 0.7;
uniform float back_scatter           : hint_range(0.0, 1.0) = 0.3;
uniform float base_brightness        : hint_range(0.0, 1.0) = 0.8;
uniform float phase_factor           : hint_range(0.0, 1.0) = 0.15;

group_uniforms Couleurs;
uniform vec4 col_a : source_color = vec4(1.0,  1.0,  1.0,  1.0);
uniform vec4 col_b : source_color = vec4(0.60, 0.65, 0.75, 1.0);

group_uniforms Marche;
uniform int   num_steps_main  : hint_range(8, 256) = 24;
uniform int   num_steps_light : hint_range(1, 16)  = 3;
uniform float ray_offset_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms Opacite;
uniform float fade_start    : hint_range(10.0,  20000.0) = 600.0;
uniform float fade_distance : hint_range(50.0,  40000.0) = 1800.0;

// ─────────────────────────────────────────────
//  VARYING
// ─────────────────────────────────────────────

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// ─────────────────────────────────────────────
//  VALUE NOISE 3D
// ─────────────────────────────────────────────

float hash1(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash1(i+vec3(0,0,0)), hash1(i+vec3(1,0,0)), u.x),
		    mix(hash1(i+vec3(0,1,0)), hash1(i+vec3(1,1,0)), u.x), u.y),
		mix(mix(hash1(i+vec3(0,0,1)), hash1(i+vec3(1,0,1)), u.x),
		    mix(hash1(i+vec3(0,1,1)), hash1(i+vec3(1,1,1)), u.x), u.y),
		u.z);
}

// FBM 4 octaves
float fbm_shape(vec3 p) {
	float v = 0.0;
	v += vnoise(p)        * 0.500;
	v += vnoise(p * 2.07) * 0.250;
	v += vnoise(p * 4.17) * 0.125;
	v += vnoise(p * 8.31) * 0.063;
	// Retourne [0, ~0.94], on normalise vers [0,1]
	return clamp(v / 0.938, 0.0, 1.0);
}

// FBM 2 octaves pour le détail
float fbm_detail(vec3 p) {
	return clamp(vnoise(p) * 0.6 + vnoise(p * 2.13) * 0.4, 0.0, 1.0);
}

// ─────────────────────────────────────────────
//  DENSITÉ
// ─────────────────────────────────────────────

float sample_density(vec3 pos, vec3 bmin, vec3 bmax) {
	vec3 size = bmax - bmin;
	vec3 uvw  = (pos - bmin) / max(size, vec3(0.001));

	// Gradient vertical : fondu en bas et en haut
	float ht    = clamp(uvw.y, 0.0, 1.0);
	float hgrad = smoothstep(0.0, bottom_fade, ht) * smoothstep(1.0, top_fade, ht);


	// Fondu bords latéraux
	float dx = min(uvw.x, 1.0 - uvw.x);
	float dz = min(uvw.z, 1.0 - uvw.z);
	float edge = smoothstep(0.0, 0.08, min(dx, dz));
	hgrad *= edge;

	if (hgrad < 0.001) {
		return 0.0;
	}

	// Bruit en coordonnées MONDE décalé par le vent.
	// Le vent déplace le bruit dans le monde → les nuages "voyagent".
	const float WORLD_SCALE = 1.0 / 3000.0;
	vec3  wind_offset = normalize(wind_direction) * wind_speed * TIME * WORLD_SCALE;
	vec3  noise_pos   = pos * WORLD_SCALE * cloud_scale + wind_offset;
	float shape = fbm_shape(noise_pos);

	// Applique le gradient : le nuage existe seulement là où le gradient est fort
	// density_offset contrôle directement à partir de quelle valeur de noise on a du nuage
	float base = (shape - (1.0 - density_offset * 0.4)) * hgrad;

	float result = 0.0;
	if (base > 0.0) {
		vec3  detail_pos = pos * WORLD_SCALE * cloud_scale + wind_offset * wind_detail_factor;
		float detail = fbm_detail(detail_pos * detail_scale);
		// Érosion : erode plus les zones à faible densité (bords)
		float erode = pow(1.0 - clamp(shape, 0.0, 1.0), 2.0);
		float d     = base - (1.0 - detail) * erode * detail_weight;
		result      = max(0.0, d * density_multiplier);
	}
	return result;
}

// ─────────────────────────────────────────────
//  RAY / BOÎTE AABB
// ─────────────────────────────────────────────

vec2 ray_box(vec3 bmin, vec3 bmax, vec3 ro, vec3 rd) {
	vec3 inv = 1.0 / rd;
	vec3 t0  = (bmin - ro) * inv;
	vec3 t1  = (bmax - ro) * inv;
	vec3 tmi = min(t0, t1);
	vec3 tma = max(t0, t1);
	float dA = max(max(tmi.x, tmi.y), tmi.z);
	float dB = min(tma.x, min(tma.y, tma.z));
	return vec2(max(0.0, dA), max(0.0, dB - max(0.0, dA)));
}

// ─────────────────────────────────────────────
//  LIGHTMARCH
// ─────────────────────────────────────────────

float lightmarch(vec3 pos, vec3 bmin, vec3 bmax) {
	vec3  sun  = normalize(light_dir);
	float ldst = ray_box(bmin, bmax, pos, sun).y;
	if (ldst < 0.001) {
		return 1.0;
	}
	float step = ldst / float(num_steps_light);
	float tot  = 0.0;
	for (int i = 0; i < num_steps_light; i++) {
		tot += sample_density(pos + sun * step * (float(i) + 1.0), bmin, bmax) * step;
	}
	float tr = exp(-max(tot, 0.0) * light_absorption_sun);
	return darkness_threshold + tr * (1.0 - darkness_threshold);
}

// ─────────────────────────────────────────────
//  PHASE HG
// ─────────────────────────────────────────────

float hg(float ca, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * 3.14159 * pow(max(1e-4, 1.0 + g2 - 2.0 * g * ca), 1.5));
}

float phase_fn(float ca) {
	return base_brightness + (hg(ca, forward_scatter) * 0.5 + hg(ca, -back_scatter) * 0.5) * phase_factor;
}

// ─────────────────────────────────────────────
//  FRAGMENT
// ─────────────────────────────────────────────

void fragment() {
	vec3 mpos = MODEL_MATRIX[3].xyz;
	vec3 mscl = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	vec3 bmin = mpos - mscl * 0.5;
	vec3 bmax = mpos + mscl * 0.5;

	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(v_world - ro);

	vec2  bi     = ray_box(bmin, bmax, ro, rd);
	float dst_to = bi.x;
	float dst_in = bi.y;

	// Caméra dans la boîte : on part de ro directement jusqu'à la sortie
	bool cam_inside = all(greaterThan(ro, bmin)) && all(lessThan(ro, bmax));
	if (cam_inside) {
		vec3 inv2 = 1.0 / rd;
		vec3 ta   = (bmin - ro) * inv2;
		vec3 tb   = (bmax - ro) * inv2;
		vec3 tmax = max(ta, tb);
		dst_to = 0.0;
		dst_in = min(tmax.x, min(tmax.y, tmax.z));
	}

	vec3  out_col   = vec3(0.0);
	float out_alpha = 0.0;

	if (dst_in > 0.001) {
		float step_sz = dst_in / float(num_steps_main);
		float rand    = fract(sin(dot(SCREEN_UV, vec2(127.1, 311.7))) * 43758.5453);
		float t       = dst_to + rand * step_sz * ray_offset_strength;

		float cos_a  = dot(rd, normalize(light_dir));
		float pval   = phase_fn(cos_a);
		float transm = 1.0;
		float lener  = 0.0;

		for (int i = 0; i < num_steps_main; i++) {
			if (t >= dst_to + dst_in) {
				break;
			}
			vec3  pos = ro + rd * t;
			float den = sample_density(pos, bmin, bmax);
			if (den > 0.0) {
				float lt  = lightmarch(pos, bmin, bmax);
				lener    += den * step_sz * transm * lt * pval;
				transm   *= exp(-den * step_sz * light_absorption_cloud);
				if (transm < 0.02) {
					break;
				}
			}
			t += step_sz;
		}

		float cam_dist  = length(v_world - ro);
		float dist_fade = 1.0 - smoothstep(fade_start, fade_distance, cam_dist);

		out_col   = mix(col_b.rgb, col_a.rgb, clamp(lener, 0.0, 1.0)) * light_color.rgb;
		out_alpha = clamp((1.0 - transm) * dist_fade, 0.0, 1.0);
	}

	ALBEDO = out_col;
	ALPHA  = out_alpha;
	
}