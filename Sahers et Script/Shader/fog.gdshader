shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, skip_vertex_transform, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture  : hint_depth_texture,  filter_nearest;

uniform mat4 inv_projection_matrix;
uniform mat4 camera_transform;
uniform vec3 player_world_pos;

uniform float blur_radius_start = 6.0;
uniform float blur_radius_end   = 10.0;
uniform float blur_max_size     = 0.008;
uniform int   blur_samples      = 8;

varying vec2 uv_interp;

void vertex() {
    // Positionne le quad directement en clip space, indépendant de la caméra
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
    uv_interp = VERTEX.xy * 0.5 + 0.5;
}

vec3 world_pos_from_depth(vec2 uv, float raw_depth) {
    // Correction Reversed-Z Vulkan
    float depth = raw_depth * 2.0 - 1.0;
    vec4 ndc      = vec4(uv * 2.0 - 1.0, depth, 1.0);
    vec4 view_pos = inv_projection_matrix * ndc;
    view_pos     /= view_pos.w;
    return (camera_transform * view_pos).xyz;
}

void fragment() {
    vec2  uv        = uv_interp;
    float raw_depth = texture(depth_texture, uv).r;
    vec3  wpos      = world_pos_from_depth(uv, raw_depth);
    float dist      = distance(wpos, player_world_pos);

    float t = smoothstep(blur_radius_start, blur_radius_end, dist);

    vec4 base = texture(screen_texture, uv);

    float size = t * blur_max_size;
    vec4  col  = vec4(0.0);

    for (int i = 0; i < blur_samples; i++) {
        float angle  = float(i) * 2.399963;
        float radius = sqrt(float(i + 1) / float(blur_samples));
        vec2  offset = vec2(cos(angle), sin(angle)) * radius * size;
        col += texture(screen_texture, uv + offset);
    }
    col /= float(blur_samples);

    // Pas de return : on mixe directement, si t=0 on garde base intact
    ALBEDO = mix(base.rgb, col.rgb, t);
}