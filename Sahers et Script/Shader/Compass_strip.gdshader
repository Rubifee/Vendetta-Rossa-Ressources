shader_type canvas_item;

uniform float offset    : hint_range(0.0, 1.0) = 0.0;
uniform float fov_ratio : hint_range(0.0, 1.0) = 0.25;
uniform float bar_width : hint_range(1.0, 4096.0) = 800.0;  // ← NOUVEAU
uniform float tex_width : hint_range(1.0, 8192.0) = 1024.0; // ← NOUVEAU

void fragment() {
    // Fraction réellement visible à l'échelle 1:1 pixel
    float visible = bar_width / tex_width;
    float u = mod(offset - visible * 0.5 + UV.x * visible, 1.0);
    COLOR = texture(TEXTURE, vec2(u, UV.y));
}