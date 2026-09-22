extends SceneTree
## Rebuild derived library from original meshes/materials; never edits source textures.


func _initialize() -> void:
	var library_uid := ResourceLoader.get_resource_uid(
		"res://assets/grid_map/forest_procedural_library.tres"
	)
	var catalog_uid := ResourceLoader.get_resource_uid(
		"res://resources/procedural/forest_tile_catalog.tres"
	)
	var source := load("res://assets/grid_map/forest_grid_map_library.tres") as MeshLibrary
	var library := source.duplicate() as MeshLibrary
	var catalog := TileCatalog.new()
	catalog.mesh_library = library
	catalog.catalog_version = "3"

	for id in library.get_item_list():
		var mesh := library.get_item_mesh(id)
		var name := library.get_item_name(id)
		if name.begins_with("floor_"):
			var shape := BoxShape3D.new()
			shape.size = Vector3(2, 0.2, 2)
			library.set_item_shapes(id, [shape, Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0))])
		elif name.begins_with("stair_small_"):
			# These two meshes are always placed as a pair. Their joining caps
			# occupy the same plane; retain only the visible outside surfaces.
			library.set_item_mesh(id, _stair_mesh(mesh, name.ends_with("left")))

			var shape := ConvexPolygonShape3D.new()
			shape.points = PackedVector3Array(
				[
					Vector3(-1, -1, -1),
					Vector3(1, -1, -1),
					Vector3(-1, -1, 1),
					Vector3(1, -1, 1),
					Vector3(-1, 1, -1),
					Vector3(1, 1, -1)
				]
			)
			library.set_item_shapes(id, [shape, Transform3D.IDENTITY])
		else:
			library.set_item_shapes(id, [mesh.create_trimesh_shape(), Transform3D.IDENTITY])

		if name.begins_with("floor_ground_"):
			var rule := _rule(name, TileRule.Group.GROUND, "ground", name)
			rule.weight = 6.0 if name.ends_with("0") else 1.0
			catalog.rules.append(rule)

	for mask in range(16):
		for diagonal in range(16):
			var name := "path_%02d_%02d" % [mask, diagonal]
			var mesh := _path_mesh(source, mask, diagonal)
			var id := library.get_last_unused_item_id()
			library.create_item(id)
			library.set_item_name(id, name)
			library.set_item_mesh(id, mesh)
			library.set_item_shapes(id, library.get_item_shapes(0))

			var rule := _rule(name, TileRule.Group.PATH, "ground", name)
			rule.neighbor_mask = mask
			rule.diagonal_mask = diagonal
			catalog.rules.append(rule)

	for mask in range(1, 16):
		var name := "cliff_%02d" % mask
		var mesh := _wall_mesh(source, mask)
		var id := library.get_last_unused_item_id()
		library.create_item(id)
		library.set_item_name(id, name)
		library.set_item_mesh(id, mesh)
		library.set_item_shapes(id, [mesh.create_trimesh_shape(), Transform3D.IDENTITY])

		var rule := _rule(name, TileRule.Group.WALL, "structures", name)
		rule.neighbor_mask = mask
		catalog.rules.append(rule)

	var stair := _rule("stairs_pair", TileRule.Group.STAIRS, "structures", "stair_small_left")
	var right := TilePlacement.new()
	right.layer = "structures"
	right.item_name = &"stair_small_right"
	right.cell = Vector3i.RIGHT
	stair.placements.append(right)
	stair.occupied_cells = [Vector2i.ZERO, Vector2i.RIGHT]
	stair.entrance_offset = Vector3i(0, -1, 1)
	stair.exit_offset = Vector3i(0, 0, -1)
	stair.height_delta = 1
	stair.allowed_rotations = PackedInt32Array([0, 1, 2, 3])
	stair.notes = "Two halves spanning 4m in width and 2m in height, ascending toward -Z. Collision ramp angle: 45 degrees."
	catalog.rules.append(stair)

	# Preserve the pixel-art palette on floors; light only the vertical relief.
	for item_id in library.get_item_list():
		var mesh := library.get_item_mesh(item_id).duplicate() as ArrayMesh
		var floor_item := (
			library.get_item_name(item_id).begins_with("floor_")
			or library.get_item_name(item_id).begins_with("path_")
		)

		for surface in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface).duplicate() as StandardMaterial3D
			material.roughness = 1.0
			material.metallic_specular = 0.0
			if floor_item:
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

			mesh.surface_set_material(surface, material)

		library.set_item_mesh(item_id, mesh)

	var err := ResourceSaver.save(library, "res://assets/grid_map/forest_procedural_library.tres")
	if err == OK:
		if library_uid != ResourceUID.INVALID_ID:
			ResourceSaver.set_uid(
				"res://assets/grid_map/forest_procedural_library.tres", library_uid
			)

		# Reload makes the catalog refer to the saved external library.
		catalog.mesh_library = load("res://assets/grid_map/forest_procedural_library.tres")
		err = ResourceSaver.save(catalog, "res://resources/procedural/forest_tile_catalog.tres")
		if err == OK and catalog_uid != ResourceUID.INVALID_ID:
			ResourceSaver.set_uid(
				"res://resources/procedural/forest_tile_catalog.tres", catalog_uid
			)

	print("Forest catalog: ", catalog.rules.size(), " rules; save error=", err)
	quit(0 if err == OK else 1)


func _rule(id: String, group: TileRule.Group, layer: String, mesh: String) -> TileRule:
	var rule := TileRule.new()
	rule.rule_id = StringName(id)
	rule.group = group
	rule.enabled = true
	rule.verified = true
	rule.notes = "Template generated from the source mesh/UVs; see tile_preview.tscn."

	var placement := TilePlacement.new()
	placement.item_name = StringName(mesh)
	placement.layer = layer
	rule.placements = [placement]

	return rule


func _path_mesh(source: MeshLibrary, mask: int, diagonal: int) -> ArrayMesh:
	var result := ArrayMesh.new()
	# Canonical NW quarter, then NW/NE/SE/SW rotations about +Y.
	var turns := [0, 3, 2, 1]
	var sides := [[1, 8, 8], [2, 1, 1], [4, 2, 2], [8, 4, 4]]

	for corner in range(4):
		var a: bool = (mask & sides[corner][0]) != 0
		var b: bool = (mask & sides[corner][1]) != 0
		var d: bool = (diagonal & sides[corner][2]) != 0
		var texture_name := "floor_path_%d" % ((mask + corner) % 3)
		var texture_turn := 0
		var fill := false
		if a and b:
			if d:
				fill = true
			else:
				texture_name = "floor_path_corner_in"
				texture_turn = 3
		elif not a and not b:
			texture_name = "floor_path_corner_out"
			texture_turn = 1
		elif a:
			texture_turn = 1

		var source_mesh := source.get_item_mesh(source.find_item_by_name(texture_name))
		var material := source_mesh.surface_get_material(0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(material)

		var basis := Basis(Vector3.UP, turns[corner] * PI / 2.0)
		var corners := [Vector3(-1, 1, -1), Vector3(0, 1, -1), Vector3(0, 1, 0), Vector3(-1, 1, 0)]

		for index in [0, 1, 2, 0, 2, 3]:
			var v: Vector3 = corners[index]
			var q := Vector2(v.x + 1.0, v.z + 1.0)

			for unused in range(texture_turn):
				q = Vector2(1.0 - q.y, q.x)

			var uv := Vector2(0.03125, 0.46875) + q * 0.5
			if fill:
				uv = Vector2(0.0625, 0.78125) + q * Vector2(0.4375, 0.15625)

			st.set_uv(uv)
			st.set_normal(Vector3.UP)
			st.add_vertex(basis * v)

		st.commit(result)

	return result


func _wall_mesh(source: MeshLibrary, mask: int) -> ArrayMesh:
	var result := ArrayMesh.new()
	var original := source.get_item_mesh(source.find_item_by_name("wall_small"))
	var arrays := original.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(original.surface_get_material(0))

	for direction in range(4):
		if (mask & (1 << direction)) == 0:
			continue

		var basis := Basis(Vector3.UP, [2, 1, 0, 3][direction] * PI / 2.0)

		for t in range(0, indices.size(), 3):
			var normal := normals[indices[t]]
			# The source is a solid, indented wall. Copy only its outward face:
			# caps otherwise overlap adjacent walls and perpendicular corners.
			if normal.z < 0.9:
				continue

			for j in range(3):
				var i := indices[t + j]
				# Flatten the decorative recess onto the cell boundary and snap
				# source export noise to its 16-pixel grid. Preserve the source UVs.
				var vertex := Vector3(
					snappedf(vertices[i].x, 0.125), snappedf(vertices[i].y, 0.125), 1.0
				)
				st.set_normal(basis * Vector3.BACK)
				st.set_uv(uvs[i])
				st.add_vertex((basis * vertex).snapped(Vector3.ONE * 0.125))

	st.commit(result)

	return result


func _stair_mesh(original: Mesh, left_half: bool) -> ArrayMesh:
	var result := ArrayMesh.new()
	var seam := 1.0 if left_half else -1.0

	for surface in range(original.get_surface_count()):
		var arrays := original.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(original.surface_get_material(surface))

		for t in range(0, indices.size(), 3):
			if (
				absf(vertices[indices[t]].x - seam) < 0.0001
				and absf(vertices[indices[t + 1]].x - seam) < 0.0001
				and absf(vertices[indices[t + 2]].x - seam) < 0.0001
			):
				continue

			for j in range(3):
				var i := indices[t + j]
				st.set_normal(normals[i])
				st.set_uv(uvs[i])
				st.add_vertex(vertices[i])

		st.commit(result)

	return result
