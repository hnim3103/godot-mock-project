extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)


func signature(result: Dictionary) -> String:
	var data: MapData = result.data
	var parts := [
		str(data.terrain_types), str(data.height_levels), str(data.stairs), str(data.spawns)
	]
	for p: TilePlacement in result.placements:
		parts.append("%s:%s:%s:%d" % [p.layer, p.cell, p.item_name, p.quarter_turns])

	return "|".join(parts).sha256_text()


func _run() -> void:
	var packed := load("res://scenes/procedural_map.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)

	var gen := scene.get_node("MapGenerator") as MapGenerator
	gen.config = gen.config.duplicate()
	check(gen.validate_dependencies().is_empty(), "Dependencies: %s" % gen.validate_dependencies())

	var start := Time.get_ticks_msec()
	var seed_count := 5 if "--quick" in OS.get_cmdline_user_args() else 100

	for seed_value in range(seed_count):
		var result := gen.prepare(seed_value)
		check(result.errors.is_empty(), "Seed %d: %s" % [seed_value, result.errors])
		if not result.errors.is_empty():
			continue

		var data: MapData = result.data
		check(data.spawns.size() == 12, "Exact spawn count, seed %d" % seed_value)
		check(not data.stairs.is_empty(), "Elevated map has stairs, seed %d" % seed_value)
		if seed_value in [0, 17, 99]:
			check(
				signature(result) == signature(gen.prepare(seed_value)),
				"Determinism seed %d" % seed_value
			)

	var initial := gen.prepare(2026)
	check(initial.errors.is_empty(), "Reference seed")
	if initial.errors.is_empty():
		gen.config.enemy_spawn_count += 1

		var changed := gen.prepare(2026)
		check(changed.errors.is_empty(), "Changed spawn count succeeds")
		if changed.errors.is_empty():
			check(
				(
					initial.data.height_levels == changed.data.height_levels
					and initial.data.terrain_types == changed.data.terrain_types
				),
				"Spawn RNG does not change layout"
			)

		gen.config.enemy_spawn_count -= 1

	gen.config.enable_elevation = false

	for seed_value in range(10):
		var result := gen.prepare(seed_value)
		check(result.errors.is_empty(), "Flat map seed %d" % seed_value)

	gen.config.enable_elevation = true
	gen.config.allow_main_path_elevation = true

	for seed_value in range(10):
		var result := gen.prepare(seed_value)
		check(
			result.errors.is_empty(),
			"Main path elevation seed %d: %s" % [seed_value, result.errors]
		)

	gen.config.allow_main_path_elevation = false

	for size in [24, 48, 64]:
		gen.config.map_size = Vector2i.ONE * size

		var result := gen.prepare(12345)
		check(result.errors.is_empty(), "Map size %d: %s" % [size, result.errors])

	gen.config.map_size = Vector2i(32, 32)
	check(gen.generate(12345), "Build real scene")

	var old_data := gen.current_data
	var old_cells := gen.ground_grid.get_used_cells().size()
	var old_markers := gen.spawn_markers.get_child_count()
	check(gen.regenerate(), "Regenerate")
	check(
		(
			gen.ground_grid.get_used_cells().size() == old_cells
			and gen.spawn_markers.get_child_count() == old_markers
		),
		"Regenerate leaves no stale cells/markers"
	)
	old_data = gen.current_data
	gen.config.path_width = 1000
	check(not gen.generate(12), "Invalid config rejected")
	check(
		gen.current_data == old_data and gen.ground_grid.get_used_cells().size() == old_cells,
		"Failed generation preserves old map"
	)
	gen.config.path_width = 2
	check(
		gen.find_children("*", "NavigationRegion3D", true, false).is_empty(),
		"Generation does not create navigation"
	)
	await physics_frame
	await physics_frame

	# Physics rays test collision on actual rendered floor and ramps.
	var space := gen.get_world_3d().direct_space_state

	for cell in [gen.current_data.start_cell, gen.current_data.exit_cell]:
		var world := gen.cell_world(cell)
		var query := PhysicsRayQueryParameters3D.create(
			world + Vector3.UP * 8, world - Vector3.UP * 2, 1
		)
		var hit := space.intersect_ray(query)
		check(
			not hit.is_empty() and absf(hit.position.y - world.y) < 0.05,
			"Floor collider matches surface"
		)

	for cell in gen.current_data.stair_cells:
		var info: Dictionary = gen.current_data.stair_cells[cell]
		var local := gen.structure_grid.map_to_local(Vector3i(cell.x, info.level, cell.y))
		var world := gen.structure_grid.to_global(local)
		var query := PhysicsRayQueryParameters3D.create(
			world + Vector3.UP * 4, world - Vector3.UP * 4, 1
		)
		var hit := space.intersect_ray(query)
		check(
			not hit.is_empty() and absf(hit.position.y - world.y) < 0.1, "Ramp collision midpoint"
		)

	gen.clear_map()
	check(
		(
			gen.current_data == null
			and gen.ground_grid.get_used_cells().is_empty()
			and gen.structure_grid.get_used_cells().is_empty()
			and gen.spawn_markers.get_child_count() == 0
		),
		"Clear removes generated state"
	)
	scene.free()
	print(
		(
			"Generation: %d checks, %d failures, %.2fs"
			% [checks, failures, (Time.get_ticks_msec() - start) / 1000.0]
		)
	)
	quit(0 if failures == 0 else 1)
