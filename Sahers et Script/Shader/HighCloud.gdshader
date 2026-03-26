shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

group_uniforms Appearance;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 sky_color   : source_color = vec4(0.4, 0.6, 1.0, 0.0);
uniform float coverage   : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float softness   : hint_range(0.0, 1.0, 0.01) = 0.4;

group_uniforms Shape;
uniform float scale : hint_range(1.0, 5000.0, 1.0) = 200.0;
uniform float height_fake: hint_range(0.0, 2.0, 0.01) = 0.6; // fausse impression de volume
uniform int   octaves    : hint_range(1, 8, 1) = 5;

group_uniforms Animation;
uniform float speed      : hint_range(0.0, 1.0, 0.001) = 0.02;
uniform vec2  direction  = vec2(1.0, 0.3);

group_uniforms;

varying vec2 v_uv_world;

// Hash
float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

// Noise doux
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f); // smoothstep

    return mix(
        mix(hash(i + vec2(0,0)), hash(i + vec2(1,0)), u.x),
        mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x),
        u.y
    );
}

// FBM — plusieurs octaves de bruit superposées
float fbm(vec2 p) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < octaves; i++) {
        val  += noise(p * freq) * amp;
        freq *= 2.0;
        amp  *= 0.5;
    }
    return val;
}

void vertex() {
    v_uv_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec2 uv = v_uv_world / scale;
    vec2 anim = direction * TIME * speed;

    // Domain warping : on déforme les UVs avec un premier bruit
    vec2 warp = vec2(
        fbm(uv + anim + vec2(0.0, 0.0)),
        fbm(uv + anim + vec2(5.2, 1.3))
    );

    // Deuxième warp pour encore plus d'organicité
    vec2 warp2 = vec2(
        fbm(uv + 2.0 * warp + anim + vec2(1.7, 9.2)),
        fbm(uv + 2.0 * warp + anim + vec2(8.3, 2.8))
    );

    // FBM final sur les UVs déformées
    float cloud = fbm(uv + 2.5 * warp2 + anim);

    // Seuil + softness
    float threshold = 1.0 - coverage;
    float alpha = smoothstep(threshold, threshold + softness, cloud);

    float light = smoothstep(threshold, threshold + softness + 0.3, cloud);
    vec3 color = mix(sky_color.rgb, cloud_color.rgb, light);

    ALBEDO = color;
    ALPHA = alpha;
}