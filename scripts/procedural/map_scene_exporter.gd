extends RefCounted
## Snapshot map geometry, collision, spawn markers and plateau areas without runtime actors.


static func pack_map(generator: MapGenerator) -> PackedScene:
	if not is_instance_valid(generator) or generator.is_generating or not generator.has_generated:
		return null

	var data := generator.current_data
	var root := Node3D.new()
	root.name = "ForestMap"
	root.set_meta("seed", data.used_seed)
	root.set_meta("map_size", data.size)
	root.set_meta("generator_version", data.generator_version)
	root.set_meta("catalog_version", data.catalog_version)
	root.set_meta("stair_flights", _collect_stair_flights(generator))

	_add_geometry(generator, root)
	_add_spawn_markers(generator, root)
	_add_map_areas(generator, root)
	_set_owner(root, root)

	var packed := PackedScene.new()
	var error := packed.pack(root)
	root.free()
	return packed if error == OK else null


static func save_map(generator: MapGenerator, path: String, overwrite: bool = false) -> Error:
	if path.get_extension().to_lower() != "tscn" or path.contains(".."):
		return ERR_INVALID_PARAMETER
	if not (
		path.begins_with("res://")
		or path.begins_with("user://")
		or path.is_absolute_path()
	):
		return ERR_INVALID_PARAMETER
	if FileAccess.file_exists(path) and not overwrite:
		return ERR_ALREADY_EXISTS

	var packed := pack_map(generator)
	if packed == null:
		return ERR_UNCONFIGURED

	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error

	# Replace the destination only after a complete snapshot has been saved.
	var temporary := path.get_basename() + ".saving_%d.tscn" % Time.get_ticks_usec()
	error = ResourceSaver.save(packed, temporary)
	if error == OK:
		error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temporary),
			ProjectSettings.globalize_path(path)
		)
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return error


static func _add_geometry(generator: MapGenerator, root: Node3D) -> void:
	for source in [generator.ground_grid, generator.structure_grid]:
		var grid := source.duplicate(0) as GridMap
		grid.bake_navigation = false
		root.add_child(grid)

	var boundary := generator.generated_objects.get_node_or_null("MapBoundary")
	if boundary != null:
		root.add_child(boundary.duplicate(0))


static func _add_spawn_markers(generator: MapGenerator, root: Node3D) -> void:
	var data := generator.current_data
	var markers := Node3D.new()
	markers.name = "SpawnMarkers"
	root.add_child(markers)

	var counts: Dictionary = {}
	for entry in data.spawns:
		var kind: StringName = entry.kind
		var cell: Vector2i = entry.cell
		var index: int = counts.get(kind, 0)
		counts[kind] = index + 1

		var marker := Marker3D.new()
		marker.name = _spawn_name(kind, index)
		marker.position = _cell_position(generator, cell)
		marker.set_meta("kind", kind)
		marker.set_meta("cell", cell)
		if kind == &"enemy":
			var area_index: int = data.region_ids[data.get_index(cell)]
			var home_area_id := _area_id(area_index) if area_index >= 0 else &""
			marker.set_meta("home_area_id", home_area_id)
		markers.add_child(marker)


static func _add_map_areas(generator: MapGenerator, root: Node3D) -> void:
	var data := generator.current_data
	var cell_size := generator.config.cell_size
	var areas := Node3D.new()
	areas.name = "MapAreas"
	root.add_child(areas)

	for index in range(data.plateaus.size()):
		var plateau: Rect2i = data.plateaus[index]
		var first := _cell_position(generator, plateau.position)
		# Rect2i.end is exclusive; subtract ONE to get the last cell center.
		var last := _cell_position(generator, plateau.end - Vector2i.ONE)
		var size_xz := Vector2(
			plateau.size.x * cell_size.x,
			plateau.size.y * cell_size.z
		)

		var area := Marker3D.new()
		area.name = _area_id(index)
		area.position = (first + last) * 0.5
		area.set_meta("area_id", _area_id(index))
		area.set_meta("kind", &"plateau")
		area.set_meta("size_xz", size_xz)
		area.set_meta("height_level", data.get_height(plateau.position))
		area.set_meta("grid_rect", plateau)
		areas.add_child(area)


static func _collect_stair_flights(generator: MapGenerator) -> Array[Dictionary]:
	# Landmarks are authoring/test data, not a navigation mesh.
	var flights: Array[Dictionary] = []
	for flight in generator.current_data.stairs:
		var entrances := PackedVector3Array()
		var exits := PackedVector3Array()
		for cell in flight.entrances:
			entrances.append(_cell_position(generator, cell))
		for cell in flight.exits:
			exits.append(_cell_position(generator, cell))
		flights.append({"entrances": entrances, "exits": exits})
	return flights


static func _cell_position(generator: MapGenerator, cell: Vector2i) -> Vector3:
	# Saved maps must not inherit the preview generator's world transform.
	return generator.to_local(generator.cell_world(cell))


static func _area_id(index: int) -> StringName:
	return StringName("Plateau_%03d" % index)


static func _spawn_name(kind: StringName, index: int) -> String:
	match kind:
		&"player":
			return "PlayerSpawn"
		&"exit":
			return "ExitSpawn"
		_:
			return "%sSpawn_%03d" % [String(kind).capitalize(), index]


static func _set_owner(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owner(child, root)
