extends SceneTree

const Exporter = preload("res://scripts/procedural/map_scene_exporter.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)


func grid_signature(grid: GridMap) -> String:
	var cells := grid.get_used_cells()
	cells.sort()

	var parts := PackedStringArray()

	for cell in cells:
		parts.append(
			"%s:%d:%d" % [cell, grid.get_cell_item(cell), grid.get_cell_item_orientation(cell)]
		)

	return "|".join(parts)


func check_map_only(node: Node) -> void:
	check(node.get_script() == null, "Saved node has no script: " + String(node.name))
	check(
		not (
			node is NavigationRegion3D
			or node is NavigationAgent3D
			or node is CharacterBody3D
			or node is Camera3D
		),
		"Only map nodes: " + String(node.name)
	)

	for child in node.get_children():
		check_map_only(child)


func _run() -> void:
	var scene := load("res://scenes/procedural_map.tscn").instantiate() as Node3D
	root.add_child(scene)

	var gen := scene.get_node("MapGenerator") as MapGenerator
	check(Exporter.pack_map(gen) == null, "Cannot export before generation")
	check(gen.generate(12345), "Generate reference map")
	gen.position = Vector3(9, 3, -7)
	gen.rotation.y = 0.4

	var ground_sig := grid_signature(gen.ground_grid)
	var structure_sig := grid_signature(gen.structure_grid)
	var start := gen.to_local(gen.cell_world(gen.current_data.start_cell))
	var count := gen.current_data.spawns.size()
	var plateaus := gen.current_data.plateaus.duplicate()
	var expected_areas: Array[Dictionary] = []

	for plateau in plateaus:
		var first := gen.to_local(gen.cell_world(plateau.position))
		var last := gen.to_local(gen.cell_world(plateau.end - Vector2i.ONE))
		(
			expected_areas
			. append(
				{
					"center": (first + last) * 0.5,
					"size_xz":
					Vector2(
						plateau.size.x * gen.config.cell_size.x,
						plateau.size.y * gen.config.cell_size.z
					),
					"height_level": gen.current_data.get_height(plateau.position),
				}
			)
		)

	var path := "/tmp/forest_export_test_%d.tscn" % Time.get_ticks_usec()
	check(Exporter.save_map(gen, path) == OK, "Save map to disk")

	var contents := FileAccess.get_file_as_string(path)
	check(Exporter.save_map(gen, path) == ERR_ALREADY_EXISTS, "Overwrite requires explicit choice")
	check(FileAccess.get_file_as_string(path) == contents, "Rejected save preserves existing file")
	check(Exporter.save_map(gen, path + ".txt") == ERR_INVALID_PARAMETER, "Reject wrong extension")
	check(
		gen.has_generated and grid_signature(gen.ground_grid) == ground_sig,
		"Export leaves preview unchanged"
	)
	# Drop all generator nodes before loading the saved map.
	scene.free()

	var packed := (
		ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	)
	check(packed != null, "Saved scene loads independently")
	if packed != null:
		var saved := packed.instantiate() as Node3D
		check_map_only(saved)
		check(
			grid_signature(saved.get_node("GroundGrid")) == ground_sig,
			"Ground cells and rotations round-trip"
		)
		check(
			grid_signature(saved.get_node("StructureGrid")) == structure_sig,
			"Structure cells and rotations round-trip"
		)
		check(
			saved.get_node("SpawnMarkers").get_child_count() == count,
			"All spawn markers serialized"
		)

		var areas := saved.get_node("MapAreas")
		check(areas.get_child_count() == plateaus.size(), "All plateaus serialized")

		for index in range(plateaus.size()):
			var area := areas.get_node("Plateau_%03d" % index) as Marker3D
			check(area.get_meta("area_id") == area.name, "Area identifier matches its node name")
			check(area.get_meta("kind") == &"plateau", "Area kind survives export")
			check(
				area.get_meta("grid_rect") == plateaus[index], "Plateau grid bounds survive export"
			)
			check(
				area.position.distance_to(expected_areas[index].center) < 0.001,
				"Area center excludes preview transform"
			)
			check(
				area.get_meta("size_xz") == expected_areas[index].size_xz,
				"Area covers complete cell footprints"
			)
			check(
				area.get_meta("height_level") == expected_areas[index].height_level,
				"Area height survives export"
			)

		for point in saved.get_node("SpawnMarkers").get_children():
			if point.get_meta("kind") != &"enemy":
				continue

			var expected_home := &""

			for index in range(plateaus.size()):
				if plateaus[index].has_point(point.get_meta("cell")):
					expected_home = StringName("Plateau_%03d" % index)

			check(
				point.get_meta("home_area_id") == expected_home,
				"Enemy marker references its containing plateau"
			)

		check(
			saved.get_node("MapBoundary").get_child_count() == 4,
			"Boundary collision shapes serialized"
		)
		check(
			saved.get_meta("seed") == 12345 and saved.get_meta("stair_flights").size() > 0,
			"Authoring metadata survives"
		)

		var marker: Marker3D = saved.get_node("SpawnMarkers/PlayerSpawn")
		check(
			marker.position.distance_to(start) < 0.001,
			"Export removes preview transform from markers"
		)
		saved.position = Vector3(-11, 4, 20)
		root.add_child(saved)
		await physics_frame
		await physics_frame

		var ground: GridMap = saved.get_node("GroundGrid")
		check(not ground.bake_navigation, "Saved GridMap does not register tile navigation")

		var point := marker.global_position
		var query := PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * 3, point - Vector3.UP, 1
		)
		var hit := saved.get_world_3d().direct_space_state.intersect_ray(query)
		check(
			not hit.is_empty() and hit.position.distance_to(point) < 0.01,
			"Reloaded, moved map retains floor collision"
		)
		saved.free()

	# Explicit replacement should serialize a new snapshot, not cached cells.
	scene = load("res://scenes/procedural_map.tscn").instantiate()
	root.add_child(scene)
	gen = scene.get_node("MapGenerator")
	check(gen.generate(17), "Generate replacement")
	check(Exporter.save_map(gen, path, true) == OK, "Explicit overwrite works")
	packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)

	var replacement := packed.instantiate()
	check(replacement.get_meta("seed") == 17, "Replacement has new seed")
	replacement.free()
	gen.clear_map()

	var before := FileAccess.get_file_as_string(path)
	check(Exporter.save_map(gen, path, true) == ERR_UNCONFIGURED, "Cannot save cleared map")
	check(FileAccess.get_file_as_string(path) == before, "Failed export preserves saved map")
	scene.free()
	DirAccess.remove_absolute(path)
	print("Map scene export: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
