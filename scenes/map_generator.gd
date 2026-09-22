class_name MapGenerator
extends Node3D
## Seeded, transactional map pipeline. Source Resources are never mutated by generation.

signal generation_started(seed_value: int)
signal generation_completed(seed_value: int)
signal generation_failed(seed_value: int, errors: PackedStringArray)
signal map_cleared

@export var config: MapConfig
@export var catalog: TileCatalog
@export var ground_grid: GridMap
@export var structure_grid: GridMap
@export var spawn_markers: Node3D
@export var generated_objects: Node3D
@export var auto_generate: bool = false

var current_data: MapData
var current_placements: Array[TilePlacement] = []
var last_seed: int = 0
var has_generated: bool = false
var is_generating: bool = false
var last_errors := PackedStringArray()
var generation_ms: float = 0.0


func _ready() -> void:
	if auto_generate:
		regenerate.call_deferred()


func validate_dependencies(full_pipeline: bool = true) -> PackedStringArray:
	var errors := _validate_resources(full_pipeline)
	if ground_grid == null or structure_grid == null or ground_grid == structure_grid:
		errors.append("Two distinct GridMaps are required.")
	elif (
		ground_grid.transform != structure_grid.transform
		or ground_grid.transform != Transform3D.IDENTITY
	):
		errors.append(
			"Child GridMaps require identity transforms; move the MapGenerator node instead."
		)

	if spawn_markers == null or generated_objects == null:
		errors.append("Missing SpawnMarkers or GeneratedObjects.")

	return errors


func _validate_resources(full_pipeline: bool = true) -> PackedStringArray:
	var errors := PackedStringArray()
	if config == null or catalog == null:
		return PackedStringArray(["Missing config/catalog."])

	errors.append_array(config.validate())
	errors.append_array(
		(
			catalog.validate_for_config(config)
			if full_pipeline
			else catalog.validate_library(config.require_collision)
		)
	)

	return errors


## Pure preparation API for tests, previews and future loading screens.
## Retry count and stage salts are deterministic; failed preparation changes no displayed map.
func prepare(seed_value: int) -> Dictionary:
	var errors := _validate_resources()
	if not errors.is_empty():
		return {"errors": errors}

	var validator := MapValidator.new()

	for attempt in range(config.max_generation_attempts):
		var data := LayoutGenerator.new().generate(config, _rng(seed_value, attempt, "layout"))
		if data == null:
			errors = PackedStringArray(["Could not place paths and spawn areas."])
			continue

		data.used_seed = seed_value
		data.attempt_index = attempt
		data.generator_version = config.generator_version
		data.catalog_version = catalog.catalog_version

		if not ElevationGenerator.new().apply(
			data, config, catalog, _rng(seed_value, attempt, "elevation")
		):
			errors = PackedStringArray(
				["Not enough room for plateaus/stairs; reduce plateau density or size."]
			)
			continue

		errors = validator.validate(data, config)
		errors.append_array(validator.validate_stairs(data, catalog))
		if not errors.is_empty():
			continue

		# Re-route the highlighted main route if elevation was allowed to cross it.
		if config.allow_main_path_elevation:
			data.main_path = validator.shortest_path(data, data.start_cell, data.exit_cell)

			for cell in data.main_path:
				data.set_terrain(cell, MapData.Terrain.PATH)

		if not SpawnPlanner.new().plan(data, config, _rng(seed_value, attempt, "spawn")):
			errors = PackedStringArray(
				["Not enough safe spawn positions; reduce spawn count or spacing."]
			)
			continue

		errors = validator.validate(data, config)
		if not errors.is_empty():
			continue

		var resolver := TileResolver.new()
		var placements := resolver.resolve(data, catalog, _rng(seed_value, attempt, "visual"))
		errors = resolver.errors.duplicate()
		errors.append_array(validator.validate_placements(placements, data, catalog))
		if errors.is_empty():
			return {"data": data, "placements": placements, "errors": errors}

	errors.insert(
		0, "Seed %d: exhausted all %d attempts." % [seed_value, config.max_generation_attempts]
	)

	return {"errors": errors}


func _rng(seed_value: int, attempt: int, stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# SHA256 avoids process-dependent/global RNG state and separates every stage.
	var bytes := (
		("%d:%d:%s:%s" % [seed_value, attempt, stage, config.generator_version]).sha256_buffer()
	)
	rng.seed = int(bytes.decode_u64(0) & 0x7fffffffffffffff)

	return rng


func generate(seed_value: int) -> bool:
	if is_generating:
		return false

	last_errors = validate_dependencies()
	if not last_errors.is_empty():
		generation_failed.emit(seed_value, last_errors)
		return false

	is_generating = true
	generation_started.emit(seed_value)

	var started := Time.get_ticks_usec()
	var prepared := prepare(seed_value)
	last_errors = prepared.errors
	if not last_errors.is_empty():
		is_generating = false
		generation_failed.emit(seed_value, last_errors)

		return false

	var builder := GridMapBuilder.new()
	if not builder.build(prepared.placements, catalog, config, ground_grid, structure_grid):
		is_generating = false
		last_errors = PackedStringArray(["Could not build GridMap."])
		generation_failed.emit(seed_value, last_errors)

		return false

	_clear_children(spawn_markers)
	_clear_children(generated_objects)

	current_data = prepared.data
	current_placements = prepared.placements
	last_seed = seed_value
	has_generated = true

	_create_markers()
	_create_boundaries()

	generation_ms = (Time.get_ticks_usec() - started) / 1000.0
	is_generating = false
	generation_completed.emit(seed_value)

	return true


func generate_random() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	return generate(rng.randi())


func regenerate() -> bool:
	if has_generated:
		return generate(last_seed)

	if config == null:
		return false

	return generate_random() if config.randomize_seed else generate(config.seed_value)


func clear_map() -> void:
	if is_generating:
		return

	if ground_grid != null and structure_grid != null:
		GridMapBuilder.new().clear_map(ground_grid, structure_grid)

	if spawn_markers != null:
		_clear_children(spawn_markers)

	if generated_objects != null:
		_clear_children(generated_objects)

	current_data = null
	current_placements.clear()
	has_generated = false
	map_cleared.emit()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.free()


func cell_world(cell: Vector2i) -> Vector3:
	return GridMapBuilder.new().cell_to_world(
		ground_grid, current_data.to_grid_cell(cell), config.ground_surface_offset
	)


func _create_markers() -> void:
	for entry in current_data.spawns:
		var marker := Marker3D.new()
		marker.name = "%s_%d_%d" % [entry.kind, entry.cell.x, entry.cell.y]
		marker.position = to_local(cell_world(entry.cell))
		marker.set_meta("kind", entry.kind)
		marker.set_meta("cell", entry.cell)
		spawn_markers.add_child(marker)

		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.16 if entry.kind == &"enemy" else 0.35
		cylinder.bottom_radius = 0.4
		cylinder.height = 1.2 if entry.kind in [&"player", &"exit"] else 0.65
		mesh.mesh = cylinder
		mesh.position.y = cylinder.height / 2.0 + 0.05

		var material := StandardMaterial3D.new()
		material.albedo_color = {
			&"player": Color("6bffe1"),
			&"exit": Color("ffd36b"),
			&"enemy": Color("ff707b"),
			&"item": Color("a19dff")
		}[entry.kind]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
		marker.add_child(mesh)


func _create_boundaries() -> void:
	var body := StaticBody3D.new()
	body.name = "MapBoundary"
	generated_objects.add_child(body)

	var origin := ground_grid.map_to_local(Vector3i.ZERO) - Vector3(1, 0, 1)
	var width := current_data.size.x * 2.0
	var depth := current_data.size.y * 2.0
	var height := config.max_height_level * 2.0 + 8.0
	var specs := [
		Vector4(-0.2, depth / 2.0, 0.4, depth + 0.8),
		Vector4(width + 0.2, depth / 2.0, 0.4, depth + 0.8),
		Vector4(width / 2.0, -0.2, width, 0.4),
		Vector4(width / 2.0, depth + 0.2, width, 0.4)
	]

	for spec in specs:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(spec.z, height, spec.w)
		collision.shape = shape
		collision.position = origin + Vector3(spec.x, height / 2.0 - 2.0, spec.y)
		body.add_child(collision)
