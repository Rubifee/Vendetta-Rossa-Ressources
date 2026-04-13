extends Node3D

@export var chunk_size   : float = 20.0
@export var view_radius  : int   = 3
@export var player       : Node3D
@export var water_height : float = 0.0

# Un mesh par LOD, du plus subdivisé au moins subdivisé
@export var lod_meshes   : Array[MeshInstance3D] = []
# Rayon (en chunks) jusqu'auquel chaque LOD s'applique
# ex: [1, 2, 3] → LOD0 jusqu'à r=1, LOD1 jusqu'à r=2, LOD2 jusqu'à r=3
@export var lod_radii    : Array[int] = [1, 2, 3]

var _multimeshes : Array[MultiMeshInstance3D] = []
var _last_center : Vector2i = Vector2i(99999, 99999)

func _ready() -> void:
	assert(lod_meshes.size() == lod_radii.size(), "lod_meshes et lod_radii doivent avoir la même taille")

	for i in lod_meshes.size():
		var mmi := MultiMeshInstance3D.new()
		add_child(mmi)

		var mm                    := MultiMesh.new()
		mm.transform_format        = MultiMesh.TRANSFORM_3D
		mm.mesh                    = lod_meshes[i].mesh
		mmi.multimesh              = mm
		mmi.material_override      = lod_meshes[i].get_active_material(0)

		_multimeshes.append(mmi)

func _process(_delta: float) -> void:
	if player == null:
		return

	var cx     := int(floor(player.global_position.x / chunk_size))
	var cz     := int(floor(player.global_position.z / chunk_size))
	var center := Vector2i(cx, cz)

	if center == _last_center:
		return
	_last_center = center

	_rebuild_instances(center)

func _rebuild_instances(center: Vector2i) -> void:
	# Un tableau de positions par LOD
	var buckets : Array[Array] = []
	for i in _multimeshes.size():
		buckets.append([])

	for dx in range(-view_radius, view_radius + 1):
		for dz in range(-view_radius, view_radius + 1):
			var dist_sq := dx * dx + dz * dz
			if dist_sq > view_radius * view_radius:
				continue

			var dist   := int(ceil(sqrt(float(dist_sq))))
			var lod_idx := _get_lod(dist)
			if lod_idx < 0:
				continue

			var world_x := (center.x + dx + 0.5) * chunk_size
			var world_z  := (center.y + dz + 0.5) * chunk_size
			var t := Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.0, 10.0, 1.0)),
				Vector3(world_x, water_height, world_z)
			)
			buckets[lod_idx].append(t)

	# Applique chaque bucket à son MultiMesh
	for i in _multimeshes.size():
		var mm  : MultiMesh          = _multimeshes[i].multimesh
		var pos : Array              = buckets[i]
		mm.instance_count            = pos.size()
		for j in pos.size():
			mm.set_instance_transform(j, pos[j])

# Retourne l'index LOD correspondant à une distance en chunks
func _get_lod(dist: int) -> int:
	for i in lod_radii.size():
		if dist <= lod_radii[i]:
			return i
	return -1
