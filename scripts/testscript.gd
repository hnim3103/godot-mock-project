extends Node3D


func _ready() -> void:
	var meshes := find_children("*", "MeshInstance3D", true, false)

	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		var aabb := mesh_instance.get_aabb()

		print("Mesh: ", mesh_instance.name)
		print("Size: ", aabb.size)
		print("Position: ", aabb.position)
