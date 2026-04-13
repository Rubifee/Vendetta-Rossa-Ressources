// CloudShadowMask.gdshader
shader_type canvas_item;

// ── Debug ─────────────────────────────────────────────
uniform bool debug_flat_red = false;

// ── Position / taille ─────────────────────────────────
uniform vec2  world_center_xz = vec2(0.0, 0.0);
uniform float coverage_size   = 2000.0;

// ── Bounds (calculés depuis MODEL_MATRIX côté GDScript) ──
uniform vec3 cloud_bmin = vec3(-500.0, 100.0, -500.0);
uniform vec3 cloud_bmax = vec3( 500.0, 300.0,  500.0);

// ── Uniforms — COPIE EXACTE du shader volumétrique ────
// Ces valeurs doivent être identiques. Le GDScript les lit
// depuis le ShaderMaterial du cloud_mesh et les recopie ici.
uniform float cloud_scale        = 2.0;
uniform float density_offset     = 0.5;
uniform float density_multiplier = 2.0;
uniform float bottom_fade        = 0.2;
uniform float top_fade           = 0.65;
uniform float detail_scale       = 3.0;
uniform float detail_weight      = 0.3;
uniform vec3  wind_direction     = vec3(1.0, 0.0, 0.3);
uniform float wind_speed         = 5.0;
uniform float wind_detail_factor = 1.4;
uniform float density_threshold  = 0.02;
uniform float edge_fade_distance : hint_range(0.0, 0.5) = 0.15;

// ── Noise (copie exacte) ───────────────────────────────

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
		mix(mix(hash1(i),             hash1(i+vec3(1,0,0)), u.x),
		    mix(hash1(i+vec3(0,1,0)), hash1(i+vec3(1,1,0)), u.x), u.y),
		mix(mix(hash1(i+vec3(0,0,1)), hash1(i+vec3(1,0,1)), u.x),
		    mix(hash1(i+vec3(0,1,1)), hash1(i+vec3(1,1,1)), u.x), u.y),
		u.z);
}

float fbm_shape(vec3 p) {
	float v  = vnoise(p)        * 0.500;
	      v += vnoise(p * 2.07) * 0.250;
	      v += vnoise(p * 4.17) * 0.125;
	return clamp(v / 0.875, 0.0, 1.0);
}

float fbm_detail(vec3 p) {
	return clamp(vnoise(p) * 0.6 + vnoise(p * 2.13) * 0.4, 0.0, 1.0);
}

// ── Densité (copie exacte) ─────────────────────────────

float sample_density(vec3 pos, vec3 wind_off) {
	vec3 size = cloud_bmax - cloud_bmin;
	vec3 uvw  = (pos - cloud_bmin) / max(size, vec3(0.001));

	float ht    = clamp(uvw.y, 0.0, 1.0);
	float hgrad = smoothstep(0.0, bottom_fade, ht) * smoothstep(1.0, top_fade, ht);

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
	if (base <= 0.0) return 0.0;

	vec3  dp     = pos * WS * cloud_scale + wind_off * wind_detail_factor;
	float detail = fbm_detail(dp * detail_scale);
	float erode  = pow(1.0 - clamp(shape, 0.0, 1.0), 2.0);
	return max(0.0, (base - (1.0 - detail) * erode * detail_weight) * density_multiplier);
}

// ── Fragment ───────────────────────────────────────────

void fragment() {
	if (debug_flat_red) {
		COLOR = vec4(1.0, 0.0, 0.0, 1.0);
	} else {
		// TIME = built-in Godot, identique au TIME du shader volumétrique.
		// Synchronisation parfaite, zéro drift, aucun uniform à gérer.
		const float WS = 1.0 / 3000.0;
		vec3 wind_off  = normalize(wind_direction) * wind_speed * TIME * WS;

		vec2  world_xz       = world_center_xz + (UV - 0.5) * coverage_size;
		float cloud_center_y = (cloud_bmin.y + cloud_bmax.y) * 0.5;
		vec3  world_pos      = vec3(world_xz.x, cloud_center_y, world_xz.y);

		float den = sample_density(world_pos, wind_off);

		vec2  dist_to_edge = min(UV, 1.0 - UV);
		float edge_factor  = min(dist_to_edge.x, dist_to_edge.y);
		float edge_fade    = smoothstep(0.0, edge_fade_distance, edge_factor);

		float alpha = (den > density_threshold) ? edge_fade : 0.0;
		COLOR = vec4(0.0, 0.0, 0.0, alpha);
	}
}
