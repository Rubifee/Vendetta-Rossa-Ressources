@tool
class_name BlurSphereEffect
extends CompositorEffect

@export var blur_radius_start: float = 6.0
@export var blur_radius_end:   float = 10.0
@export var blur_max_size:     float = 3.0
@export var blur_samples:      int   = 8

var player_world_pos: Vector3 = Vector3.ZERO

var _rd:             RenderingDevice
var _shader:         RID
var _pipeline:       RID
var _uniform_buffer: RID
var _sampler:        RID

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = false

func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	if not _pipeline.is_valid():
		_init_pipeline()
		if not _pipeline.is_valid():
			return

	var scene_buffers = render_data.get_render_scene_buffers()
	var scene_data    = render_data.get_render_scene_data()
	if not scene_buffers or not scene_data:
		return

	var size: Vector2i = scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	var color_image: RID = scene_buffers.get_color_layer(0)
	var depth_image: RID = scene_buffers.get_depth_layer(0)

	if not _sampler.is_valid():
		var ss := RDSamplerState.new()
		ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		_sampler = _rd.sampler_create(ss)

	var buf := PackedFloat32Array()

	var proj:     Projection = scene_data.get_view_projection(0)
	var inv_proj: Projection = proj.inverse()
	for col in range(4):
		for row in range(4):
			buf.append(inv_proj[col][row])

	var cm: Transform3D = scene_data.get_cam_transform()
	buf.append_array([
		cm.basis.x.x, cm.basis.x.y, cm.basis.x.z, 0.0,
		cm.basis.y.x, cm.basis.y.y, cm.basis.y.z, 0.0,
		cm.basis.z.x, cm.basis.z.y, cm.basis.z.z, 0.0,
		cm.origin.x,  cm.origin.y,  cm.origin.z,  1.0,
	])
	buf.append_array([
		player_world_pos.x, player_world_pos.y, player_world_pos.z, 0.0,
		blur_radius_start, blur_radius_end, blur_max_size, float(blur_samples),
		float(size.x), float(size.y), 0.0, 0.0,
	])

	var buf_bytes := buf.to_byte_array()
	if not _uniform_buffer.is_valid():
		_uniform_buffer = _rd.uniform_buffer_create(buf_bytes.size())
	_rd.buffer_update(_uniform_buffer, 0, buf_bytes.size(), buf_bytes)

	var u_color := RDUniform.new()
	u_color.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_color.binding      = 0
	u_color.add_id(color_image)

	var u_buf := RDUniform.new()
	u_buf.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_buf.binding      = 1
	u_buf.add_id(_uniform_buffer)

	var u_depth := RDUniform.new()
	u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_depth.binding      = 2
	u_depth.add_id(_sampler)
	u_depth.add_id(depth_image)

	var uniform_set := _rd.uniform_set_create([u_color, u_buf, u_depth], _shader, 0)

	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_dispatch(
		compute_list,
		int(ceil(size.x / 8.0)),
		int(ceil(size.y / 8.0)), 1)
	_rd.compute_list_end()
	
	_rd.free_rid(uniform_set)

func _init_pipeline() -> void:
	var src := RDShaderSource.new()
	src.language       = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = _get_shader_code()
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv == null:
		push_error("BlurSphereEffect : échec compilation shader")
		return
	_shader   = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)

func _get_shader_code() -> String:
	return """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, binding = 0) uniform image2D color_image;

layout(binding = 1) uniform Params {
	mat4  inv_projection;
	mat4  cam_transform;
	vec3  player_world_pos;
	float _pad0;
	float blur_radius_start;
	float blur_radius_end;
	float blur_max_size;
	float blur_samples;
	float screen_width;
	float screen_height;
	float _pad1;
	float _pad2;
} params;

layout(binding = 2) uniform sampler2D depth_texture;

vec3 world_pos_from_depth(vec2 uv) {
	float raw_depth = texture(depth_texture, uv).r;

	// Reversed-Z : depth == 0.0 = fond/ciel = distance infinie → pas de flou
	if (raw_depth == 0.0) return params.player_world_pos;

	vec4 ndc      = vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view_pos = params.inv_projection * ndc;
	view_pos     /= view_pos.w;
	return (params.cam_transform * view_pos).xyz;
}

void main() {
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size  = ivec2(int(params.screen_width), int(params.screen_height));
	if (coord.x >= size.x || coord.y >= size.y) return;

	vec2 uv   = (vec2(coord) + 0.5) / vec2(size);
	vec4 base = imageLoad(color_image, coord);

	vec3  wpos = world_pos_from_depth(uv);
	float dist = distance(wpos, params.player_world_pos);
	float t    = smoothstep(params.blur_radius_start, params.blur_radius_end, dist);

	if (t <= 0.001) {
		imageStore(color_image, coord, base);
		return;
	}

	float size_px = t * params.blur_max_size;
	vec4  col     = vec4(0.0);
	int   s       = int(params.blur_samples);

	for (int i = 0; i < s; i++) {
		float angle  = float(i) * 2.399963;
		float radius = sqrt(float(i + 1) / float(s));
		vec2  offset = vec2(cos(angle), sin(angle)) * radius * size_px;
		ivec2 sc     = clamp(coord + ivec2(offset), ivec2(0), size - 1);
		col += imageLoad(color_image, sc);
	}
	col /= float(s);

	imageStore(color_image, coord, mix(base, col, t));
}
"""
