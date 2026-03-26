shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;


// --- uniforms généraux
uniform float height_scale   = 0.5;
uniform float noise_scale    = 1.0;
uniform vec2  noise_offset   = vec2(0.0);
uniform float speed          = 0.5;

varying vec4  world_data;
varying vec4  wave_fields;
varying float v_calm;
varying vec3  v_world_pos;

uniform float wave_mode = 0.0;
uniform float fbm_smooth_amount = 0.4;

uniform float sin_freq1 = 1.0;
uniform float sin_amp1  = 0.35;
uniform vec2  sin_dir1  = vec2(1.0, 0.0);
uniform float sin_freq2 = 2.0;
uniform float sin_amp2  = 0.12;
uniform vec2  sin_dir2  = vec2(0.6, 0.8);
uniform float sin_freq3 = 0.5;
uniform float sin_amp3  = 0.25;

uniform float cap_height = 0.4;
uniform vec3  cap_color  = vec3(1.0, 1.0, 1.0);
uniform float foam_noise_scale = 0.5;
uniform float foam_time_speed  = 0.2;
uniform float foam_range       = 0.3;
uniform float wave2_strength = 0.7;

uniform vec4  islands[8];
uniform int   island_count   = 2;
uniform float calm_water_height = 0.5;

uniform vec3 wave_color1 = vec3(0.0, 0.2, 0.95);
uniform vec3 wave_color2 = vec3(0.0, 0.6, 0.8);
uniform vec3 wave_color3 = vec3(0.0, 0.4, 0.6);

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform float shore_foam_depth     = 0.8;
uniform float shore_foam_sharpness = 0.3;
uniform vec3  shore_foam_color     = vec3(1.0, 1.0, 1.0);
uniform float shore_foam_noise_mix = 0.5;

uniform vec2 player_xz;

const float COS_0   =  1.0;       const float SIN_0   =  0.0;
const float COS_120 = -0.5;       const float SIN_120 =  0.8660254;
const float COS_240 = -0.5;       const float SIN_240 = -0.8660254;

// ── VALUE NOISE ── pour les vagues
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// ── SIMPLEX NOISE ── pour la mousse uniquement
vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)),
             dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float snoise(vec2 p) {
    const float K1 = 0.366025404;
    const float K2 = 0.211324865;
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

float get_calm_factor(vec2 pos) {
    float calm = 1.0;
    for (int i = 0; i < 8; i++) {
        if (i >= island_count) break;
        vec2  island_pos = islands[i].xy;
        float calm_r     = islands[i].z;
        float shore_r    = islands[i].w;
        float dist = length(pos - island_pos);
        calm = min(calm, smoothstep(shore_r, calm_r, dist))+0.2;
    }
    return calm;
}

float fbm(vec2 x) {
    float h    = 0.0;
    float amp  = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 5; i++) {
        h    += noise(x * freq) * amp;
        amp  *= 0.5;
        freq *= 2.0;
    }
    return h;
}

float fbm_world_at(vec2 world_xz, vec2 drift) {
    vec2 p = world_xz * noise_scale + noise_offset + drift * (TIME * speed);
    return fbm(p);
}

float fbm_smooth_dir(vec2 world_xz, float cos_a, float sin_a, vec2 drift) {
    vec2 r = vec2(cos_a * world_xz.x - sin_a * world_xz.y,
                  sin_a * world_xz.x + cos_a * world_xz.y);
    float s  = fbm_world_at(r, drift);
    float o1 = fbm_world_at(r + vec2( fbm_smooth_amount, 0.0), drift);
    float o2 = fbm_world_at(r + vec2(-fbm_smooth_amount, 0.0), drift);
    float o3 = fbm_world_at(r + vec2(0.0,  fbm_smooth_amount), drift);
    float o4 = fbm_world_at(r + vec2(0.0, -fbm_smooth_amount), drift);
    return (s + o1 + o2 + o3 + o4) * 0.2;
}

float sin_waves(vec2 world_xz) {
    vec2  d1 = normalize(sin_dir1);
    vec2  d2 = normalize(sin_dir2);
    vec2  d3 = normalize(sin_dir2.yx * vec2(-1.0, 1.0));
    float t  = TIME * speed;
    return sin(dot(world_xz, d1) * sin_freq1 + t) * sin_amp1
         + sin(dot(world_xz, d2) * sin_freq2 + t) * sin_amp2
         + sin(dot(world_xz, d3) * sin_freq3 + t) * sin_amp3;
}

void vertex() {
    vec3 orig      = VERTEX;
    vec3 world_pos = (MODEL_MATRIX * vec4(orig, 1.0)).xyz;
    vec2 world_xz  = world_pos.xz - player_xz;
    vec2 world_xz_abs = world_pos.xz;

    float h = 0.0;
    if (wave_mode < 0.5) {
        float h1 = fbm_smooth_dir(world_xz, COS_0,   SIN_0,   vec2( 0.8,  0.3));
        float h2 = fbm_smooth_dir(world_xz, COS_120, SIN_120, vec2(-0.8,  0.3)) * wave2_strength;
        float h3 = fbm_smooth_dir(world_xz, COS_240, SIN_240, vec2( 0.8, -0.3)) * wave2_strength;
        h = (h1 + h2 + h3) * 0.3333;
        wave_fields = vec4(h1, h2, h3, 0.0);
    } else {
        h = sin_waves(world_xz);
        wave_fields = vec4(0.0);
    }

    float calm = get_calm_factor(world_xz_abs);
    v_calm      = calm;
    VERTEX.y    = mix(calm_water_height, orig.y + h * height_scale, calm);
    v_world_pos = vec3(world_pos.x, VERTEX.y, world_pos.z);
    world_data  = vec4(world_xz, h, VERTEX.y);
}

void fragment() {
    float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
    SPECULAR  = fresnel * 0.8;
    ROUGHNESS = mix(0.05, 1.0, 1.0 - fresnel) + 0.8;

    vec2  world_xz    = world_data.rg;
    float displaced_y = world_data.a;
    float calm        = v_calm;

    vec3 dx      = dFdx(v_world_pos);
    vec3 dz      = dFdy(v_world_pos);
    vec3 n_world = normalize(cross(dz, dx));
    if (!FRONT_FACING) n_world = -n_world;
    NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

    // ---- mousse de crêtes (Simplex) ----
    float foam_factor = smoothstep(cap_height, cap_height + foam_range, displaced_y);
    vec2 foam_drift = (  vec2( 0.8,  0.3)
                       + vec2(-0.8,  0.3) * 0.7
                       + vec2( 0.8, -0.3) * 0.7 ) * (TIME * speed);
    float fn = snoise(world_xz * foam_noise_scale + foam_drift * foam_time_speed);
    float foam_mask = smoothstep(0.0, 0.15, foam_factor - fn) * foam_factor;
    foam_mask *= smoothstep(0.3, 0.85, calm);

    float w1 = wave_fields.r * wave_fields.r * wave_fields.r;
    float w2 = wave_fields.g * wave_fields.g * wave_fields.g;
    float w3 = wave_fields.b * wave_fields.b * wave_fields.b;
    float total = w1 + w2 + w3 + 0.001;
    vec3 blended_color = (wave_color1 * w1 + wave_color2 * w2
                        + wave_color3 * w3) / total;

    vec3 fading_color = mix(blended_color, blended_color * 0.8, foam_factor * (1.0 - foam_mask));
    vec3 deep_color   = blended_color * 0.2;
    vec3 depth_color  = mix(deep_color, fading_color, smoothstep(0.0, height_scale, displaced_y));

    // ---- mousse de contact (Simplex) ----
    float raw_depth  = texture(depth_texture, SCREEN_UV).r;
    float shore_mask = 0.0;

    if (raw_depth < 1.0) {
        vec4 scene_view   = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
        scene_view.xyz   /= scene_view.w;
        float scene_depth = -scene_view.z;
        float water_depth = -VERTEX.z;
        float depth_diff  = scene_depth - water_depth;

        vec2  shore_drift = foam_drift * foam_time_speed * 0.6;
        float shore_n     = snoise(world_xz * foam_noise_scale * 1.4 + shore_drift + 3.7);

        float shore_raw  = 1.0 - smoothstep(0.0, shore_foam_depth, depth_diff);
        float shore_edge = smoothstep(shore_foam_sharpness, 1.0,
                                      shore_raw + shore_n * shore_foam_noise_mix);
        shore_mask = shore_edge * shore_raw;
    }

    float combined_foam = clamp(foam_mask + shore_mask, 0.0, 1.0);
    vec3  foam_col      = mix(cap_color, shore_foam_color, shore_mask / (combined_foam + 0.001));

    ALBEDO   = mix(depth_color, foam_col, combined_foam);
    EMISSION = mix(vec3(0.0), foam_col * 0.04, combined_foam);
    ALPHA    = 0.98;
}
