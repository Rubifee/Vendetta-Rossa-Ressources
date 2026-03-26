shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float blur_start = 0.99;
uniform float blur_strength = 3.0;
uniform float cam_near = 0.05;
uniform float cam_far = 100.0;

void fragment() {
    float raw = texture(depth_texture, SCREEN_UV).r;
    
    // Linéariser la profondeur
    float depth = (2.0 * cam_near) / (cam_far + cam_near - raw * (cam_far - cam_near));
    
    float amount = smoothstep(blur_start, 1.0, depth) * blur_strength;
    
    vec4 color = vec4(0.0);
    for (float x = -2.0; x <= 2.0; x++) {
        for (float y = -2.0; y <= 2.0; y++) {
            vec2 offset = vec2(x, y) * amount * 0.001;
            color += texture(screen_texture, SCREEN_UV + offset);
        }
    }
    COLOR = color / 25.0;
}