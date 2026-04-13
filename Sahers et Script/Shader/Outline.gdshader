shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture;
uniform float edge_thickness : hint_range(0.0, 5.0) = 1.0;
uniform float edge_strength  : hint_range(0.0, 10.0) = 2.0;
uniform vec4  edge_color     : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec2  inv_texture_size;

void fragment() {
    vec2 o = inv_texture_size * edge_thickness;

    vec3 c = texture(screen_texture, SCREEN_UV).rgb;
    vec3 r = texture(screen_texture, SCREEN_UV + vec2(o.x, 0.0)).rgb;
    vec3 d = texture(screen_texture, SCREEN_UV + vec2(0.0, o.y)).rgb;

    vec3 gx = r - c;
    vec3 gy = d - c;

    float edge = sqrt(dot(gx, gx) + dot(gy, gy));
    edge = smoothstep(0.1, 0.5, edge * edge_strength);

    COLOR = vec4(mix(c, edge_color.rgb, edge * edge_color.a), 1.0);
}