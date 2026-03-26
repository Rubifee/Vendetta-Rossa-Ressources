shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

uniform sampler2D albedo_texture : source_color, repeat_enable;
uniform vec2  uv_offset  = vec2(0.0);
uniform float uv_scale   = 1.0;

// --- Réflexion soleil ---
uniform vec3  sun_direction  = vec3(0.3, 0.8, 0.3);
uniform vec4  sun_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float sun_specular_power    : hint_range(1.0,  512.0) = 64.0;
uniform float sun_specular_strength : hint_range(0.0,  5.0)   = 1.0;
uniform float fresnel_strength      : hint_range(0.0,  1.0)   = 0.4;

// --- Courbure ---
uniform float earth_radius : hint_range(-1050.0, 50000.0) = 8000.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 sample_rotated(sampler2D tex, vec2 uv) {
    vec2 tile  = floor(uv);
    vec2 local = fract(uv);
    float r    = floor(hash(tile) * 4.0);
    float angle = r * 3.14159 * 0.5;
    float c = cos(angle), s = sin(angle);
    vec2 centered = local - 0.5;
    vec2 rotated  = vec2(c * centered.x - s * centered.y,
                         s * centered.x + c * centered.y) + 0.5;
    return texture(tex, rotated);
}

void vertex() {
    vec3 world_pos  = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 offset_xz  = world_pos.xz - MODEL_MATRIX[3].xz;
    float dist2     = dot(offset_xz, offset_xz);
    VERTEX.y       -= dist2 / (2.0 * earth_radius * earth_radius);
}

void fragment() {
    vec2 uv = (UV + uv_offset) * uv_scale;
    vec3 albedo = sample_rotated(albedo_texture, uv).rgb;

    float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
    fresnel *= fresnel_strength;

    vec3  sun_dir  = normalize(sun_direction);
    vec3  half_vec = normalize(VIEW + sun_dir);
    float spec     = pow(max(dot(NORMAL, half_vec), 0.0), sun_specular_power);
    vec3  specular = sun_color.rgb * spec * sun_specular_strength * fresnel;

    ALBEDO    = albedo + specular;
    SPECULAR  = fresnel * 0.8;
    ROUGHNESS = 1.0;
}