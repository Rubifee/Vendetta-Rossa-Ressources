extends ColorRect

func _ready():
	var vp = $NormalView
	vp.size = get_viewport().size
	var vp_size = vp.size  # Vector2, pas le nœud
	material.set_shader_parameter("inv_texture_size", Vector2(1.0 / vp_size.x, 1.0 / vp_size.y))
