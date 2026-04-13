#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// set=0 : images couleur (entrée + sortie, swappées entre les 2 passes)
layout(rgba16f, set = 0, binding = 0) uniform readonly  image2D input_img;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_img;

// set=1 : depth en lecture seule via sampler
layout(set = 1, binding = 0) uniform sampler2D depth_tex;

layout(push_constant, std430) uniform Params {
    vec2  screen_size;   // offset  0 (8 bytes)
    float direction;     // offset  8 — 0.0 = horizontal, 1.0 = vertical
    float near_z;        // offset 12
    float far_z;         // offset 16
    float focus_dist;    // offset 20 — distance de mise au point
    float focus_range;   // offset 24 — plage de netteté autour du focus
    float blur_amount;   // offset 28 — rayon max en pixels
} p;                     // total : 32 bytes

// Godot 4.3+ utilise Reverse-Z : near = 1.0, far = 0.0 dans le depth buffer
float linearize_depth(float d) {
    return (p.near_z * p.far_z) / (p.near_z + d * (p.far_z - p.near_z));
}

float get_coc(float lin_d) {
    return clamp((lin_d - p.focus_dist) / max(p.focus_range, 0.001), 0.0, 1.0);
}

// CoC lissé sur une fenêtre 3x3 — élimine les sauts aux bords des tuiles 8x8
float smooth_coc(ivec2 coord, ivec2 isize) {
    float sum = 0.0;
    float count = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            ivec2 sc  = clamp(coord + ivec2(dx, dy), ivec2(0), isize - 1);
            vec2  suv = (vec2(sc) + 0.5) / p.screen_size;
            float d   = linearize_depth(texture(depth_tex, suv).r);
            // Ignore le ciel dans la moyenne — utilise seulement la géométrie réelle
            if (d < p.far_z * 0.98) {
                sum   += get_coc(d);
                count += 1.0;
            }
        }
    }
    return count > 0.0 ? sum / count : 0.0;
}

void main() {
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 isize = ivec2(p.screen_size);
    if (coord.x >= isize.x || coord.y >= isize.y) return;

    vec2  uv        = (vec2(coord) + 0.5) / p.screen_size;
    float raw_depth = texture(depth_tex, uv).r;
    float lin_d     = linearize_depth(raw_depth);

    // CoC lissé → pas de saut brusque aux bords des tuiles 8x8
    float coc    = smooth_coc(coord, isize);
    float radius = coc * p.blur_amount;

    // Ciel pur ou pixel déjà net → copie directe
    if (lin_d >= p.far_z * 0.98 || radius < 0.5) {
        imageStore(output_img, coord, imageLoad(input_img, coord));
        return;
    }

    // Blur gaussien séparable (horizontal OU vertical selon p.direction)
    ivec2 dir    = p.direction < 0.5 ? ivec2(1, 0) : ivec2(0, 1);
    int   kernel = clamp(int(ceil(radius)), 1, 24);
    float sigma  = float(kernel) / 2.0;

    vec4  color  = vec4(0.0);
    float total  = 0.0;

    for (int i = -kernel; i <= kernel; i++) {
        ivec2 sc = clamp(coord + i * dir, ivec2(0), isize - 1);

        vec2  suv     = (vec2(sc) + 0.5) / p.screen_size;
        float s_raw   = texture(depth_tex, suv).r;
        float s_lin   = linearize_depth(s_raw);
        float s_coc   = (s_lin >= p.far_z * 0.98) ? coc : get_coc(s_lin);

        float gauss   = exp(-float(i * i) / (2.0 * sigma * sigma));
        float w       = gauss * max(s_coc, 0.05);

        color += imageLoad(input_img, sc) * w;
        total += w;
    }

    if (total > 0.0) color /= total;
    imageStore(output_img, coord, color);
}
