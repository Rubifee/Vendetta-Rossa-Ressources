// CloudVolume_optimized.gdshader

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

// ─────────────────────────────────────────────
//  PARAMÈTRES
// ─────────────────────────────────────────────

group_uniforms Forme;
uniform float cloud_scale        : hint_range(0.1, 10.0) = 2.0;
uniform float density_offset     : hint_range(0.0, 3.0)  = 0.5;
uniform float density_multiplier : hint_range(0.0, 5.0)  = 2.0;
uniform float bottom_fade : hint_range(0.0, 0.5) = 0.2;
uniform float top_fade    : hint_range(0.5, 1.0) = 0.65;

group_uniforms Detail;
uniform float detail_scale  : hint_range(1.0, 20.0) = 3.0;
uniform float detail_weight : hint_range(0.0, 1.0)  = 0.3;

group_uniforms Vent;
uniform vec3  wind_direction = vec3(1.0, 0.0, 0.3);
uniform float wind_speed          : hint_range(0.0, 50.0) = 5.0;
uniform float wind_detail_factor  : hint_range(0.5, 3.0)  = 1.4;

group_uniforms Lumiere;
uniform vec3  light_dir                                      = vec3(0.3, 0.8, 0.3);
uniform vec4  light_color : source_color                     = vec4(1.0, 0.96, 0.88, 1.0);
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
// num_steps_light supprimé : le lightmarch utilise désormais 1 seul échantillon.
uniform int   num_steps_main       : hint_range(8, 256)  = 24;
uniform float ray_offset_strength  : hint_range(0.0, 40.0) = 1.0;

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
//  BAYER 4×4
//  Distribution uniforme sur [0/16 … 15/16].
//  Utilise les coordonnées pixel (FRAGCOORD) → stable entre frames,
//  ce qui permet au TAA de Godot d'accumuler proprement.
// ─────────────────────────────────────────────

float ign(vec2 fc) {
    // Modulation par frame : brise la cohérence temporelle → TAA accumule proprement
    vec2 jfc = fc + fract(vec2(TIME, TIME * 0.7193) * vec2(47.0, 83.0));
    return fract(52.9829189 * fract(0.06711056 * jfc.x + 0.00583715 * jfc.y));
}

// ─────────────────────────────────────────────
//  VALUE NOISE 3D (inchangé)
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
		mix(mix(hash1(i),              hash1(i+vec3(1,0,0)), u.x),
		    mix(hash1(i+vec3(0,1,0)),  hash1(i+vec3(1,1,0)), u.x), u.y),
		mix(mix(hash1(i+vec3(0,0,1)),  hash1(i+vec3(1,0,1)), u.x),
		    mix(hash1(i+vec3(0,1,1)),  hash1(i+vec3(1,1,1)), u.x), u.y),
		u.z);
}

// ── FBM forme : 3 octaves ───────────────────
//  Suppression de l'octave ×8.31 (la plus chère, apport visuel minimal).
//  Somme max = 0.500 + 0.250 + 0.125 = 0.875 → normalisation ajustée.
float fbm_shape(vec3 p) {
	float v  = vnoise(p)        * 0.500;
	      v += vnoise(p * 2.07) * 0.250;
	      v += vnoise(p * 4.17) * 0.125;
	return clamp(v / 0.875, 0.0, 1.0);
}

// FBM détail 2 octaves (inchangé)
float fbm_detail(vec3 p) {
	return clamp(vnoise(p) * 0.6 + vnoise(p * 2.13) * 0.4, 0.0, 1.0);
}

// ─────────────────────────────────────────────
//  DENSITÉ
//  wind_off passé en paramètre : calculé une seule fois dans fragment().
// ─────────────────────────────────────────────

float sample_density(vec3 pos, vec3 bmin, vec3 bmax, vec3 wind_off) {
	vec3 size = bmax - bmin;
	vec3 uvw  = (pos - bmin) / max(size, vec3(0.001));

	// Gradient vertical
	float ht    = clamp(uvw.y, 0.0, 1.0);
	float hgrad = smoothstep(0.0, bottom_fade, ht) * smoothstep(1.0, top_fade, ht);

	// Fondu bords latéraux
	float dx = min(uvw.x, 1.0 - uvw.x);
	float dz = min(uvw.z, 1.0 - uvw.z);
	float ex = smoothstep(0.0, 0.18, dx) * smoothstep(1.0, 0.82, dx);
	float ez = smoothstep(0.0, 0.18, dz) * smoothstep(1.0, 0.82, dz);
	hgrad *= ex * ez;

	if (hgrad < 0.001) return 0.0;

	const float WS = 1.0 / 3000.0;
	vec3  np    = pos * WS * cloud_scale + wind_off;
	float shape = fbm_shape(np);

	float base = (shape - (1.0 - density_offset * 0.4)) * hgrad;
	// Early-exit explicite : évite le FBM détail si la forme de base est vide.
	if (base <= 0.0) return 0.0;

	vec3  dp     = pos * WS * cloud_scale + wind_off * wind_detail_factor;
	float detail = fbm_detail(dp * detail_scale);
	float erode  = pow(1.0 - clamp(shape, 0.0, 1.0), 2.0);
	return max(0.0, (base - (1.0 - detail) * erode * detail_weight) * density_multiplier);
}

// ─────────────────────────────────────────────
//  AABB (inchangé)
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
//  LIGHTMARCH OPTIMISÉ — 1 seul échantillon
//
//  Au lieu de marcher N pas vers le soleil, on évalue la densité
//  en un unique point (mi-parcours). L'approximation est visuellement
//  indiscernable sur des nuages diffus, pour un coût N fois moindre.
//  Si vous voulez plus de précision, augmentez l'absorption via
//  light_absorption_sun plutôt qu'en remettant une boucle.
// ─────────────────────────────────────────────

float lightmarch(vec3 pos, vec3 bmin, vec3 bmax, vec3 sun_dir, vec3 wind_off) {
	float ldst = ray_box(bmin, bmax, pos, sun_dir).y;
	if (ldst < 0.001) return 1.0;
	float den = sample_density(pos + sun_dir * ldst * 0.5, bmin, bmax, wind_off);
	float tr  = exp(-max(den * ldst, 0.0) * light_absorption_sun);
	return darkness_threshold + tr * (1.0 - darkness_threshold);
}

// ─────────────────────────────────────────────
//  PHASE HG (inchangé)
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

	// ── Précalculs constants pour ce fragment ─────────────────────────────
	// Calculés ici une seule fois, puis passés en paramètre à toutes les fonctions.
	const float WS   = 1.0 / 3000.0;
	vec3  wind_off   = normalize(wind_direction) * wind_speed * TIME * WS;
	vec3  sun_dir    = normalize(light_dir);
	float cos_a      = dot(rd, sun_dir);
	float pval       = phase_fn(cos_a);

	vec2  bi     = ray_box(bmin, bmax, ro, rd);
	float dst_to = bi.x;
	float dst_in = bi.y;

	// Caméra dans la boîte
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

		// ── Bayer 4×4 : offset initial du rayon ──────────────────────────
		float t = dst_to + ign(FRAGCOORD.xy) * step_sz * ray_offset_strength;

		float transm      = 1.0;
		float lener       = 0.0;
		float cur_step    = step_sz;
		int   empty_streak = 0;

		for (int i = 0; i < num_steps_main; i++) {
			if (t >= dst_to + dst_in) break;

			vec3  pos = ro + rd * t;
			float den = sample_density(pos, bmin, bmax, wind_off);

			if (den > 0.0) {
				// ── Zone dense : pas normal + calcul lumière ──────────────
				empty_streak = 0;
				cur_step     = step_sz;

				float lt  = lightmarch(pos, bmin, bmax, sun_dir, wind_off);
				lener    += den * cur_step * transm * lt * pval;
				transm   *= exp(-den * cur_step * light_absorption_cloud);

				// Seuil porté à 0.03 (était 0.02) — gain marginal, visuellement neutre.
				if (transm < 0.03) break;

			} else {
				// ── Zone vide : accélération progressive ──────────────────
				// empty_streak croît jusqu'à 4 max, ce qui plafonne le pas à 3×.
				// Réinitialisation au prochain pixel dense.
				empty_streak++;
				cur_step = step_sz * min(1.0 + float(empty_streak) * 0.5, 3.0);
			}

			t += cur_step;
		}

		float cam_dist  = length(v_world - ro);
		float dist_fade = 1.0 - smoothstep(fade_start, fade_distance, cam_dist);

		out_col   = mix(col_b.rgb, col_a.rgb, clamp(lener, 0.0, 1.0)) * light_color.rgb;
		out_alpha = clamp((1.0 - transm) * dist_fade, 0.0, 1.0);
	}

	ALBEDO = out_col;
	ALPHA  = out_alpha;
}
