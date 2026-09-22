extends SceneTree
## Tests implemented components; does not verify algorithms marked TODO.
## Run: godot --headless --path . --script tests/procedural/test_config_resources.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_test_config()
	_test_catalog()
	_test_data()
	_test_scene_and_scripts()
	print("Procedural support: %d checks, %d failures." % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + description)


func _test_config() -> void:
	var config := load("res://resources/procedural/forest_map_config.tres") as MapConfig
	_check(config != null, "Preset config loads with the expected type")
	if config == null:
		return

	_check(config.validate().is_empty(), "Default preset is valid")

	var changed := config.duplicate() as MapConfig
	changed.seed_value = 0
	_check(changed.validate().is_empty(), "Seed 0 is valid")
	changed.path_width = 1000
	_check(not changed.validate().is_empty(), "Reject paths wider than the map")
	_check(config.path_width == 2, "Editing a copy leaves the preset unchanged")
	changed = config.duplicate() as MapConfig
	changed.spawn_safe_radius = 20
	_check(not changed.validate().is_empty(), "Reject spawn areas exceeding the map interior")
	changed = config.duplicate() as MapConfig
	changed.cell_size.y = 0.0
	_check(not changed.validate().is_empty(), "Reject zero cell height")
	changed = config.duplicate() as MapConfig
	changed.allow_main_path_elevation = true
	changed.enable_elevation = false
	_check(
		not changed.validate().is_empty(), "Reject main path elevation when elevation is disabled"
	)


func _test_catalog() -> void:
	var catalog := load("res://resources/procedural/forest_tile_catalog.tres") as TileCatalog
	_check(catalog != null, "Catalog loads with the expected type")
	if catalog == null:
		return

	var errors := catalog.validate_library()
	_check(errors.is_empty(), "Catalog is valid: %s" % str(errors))
	_check(catalog.rules.size() == 276, "Catalog contains all ground/path/wall/stair rules")
	_check(catalog.get_rules(TileRule.Group.GROUND).size() == 4, "Four ground rules are enabled")
	_check(
		catalog.get_rules(TileRule.Group.PATH).size() == 256, "All edge/corner masks are covered"
	)
	_check(
		catalog.get_rules(TileRule.Group.STAIRS).size() == 1,
		"A two-lane stair template is available"
	)
	_check(catalog.get_rules(TileRule.Group.WALL).size() == 15, "All 15 wall masks are covered")
	_check(
		catalog.get_item_id(&"missing_item") == -1, "Missing mesh lookup returns INVALID_CELL_ITEM"
	)
	_check(
		catalog.validate_library(true).is_empty(), "All tiles used in the pipeline have collision"
	)
	_check(
		catalog.validate_for_config(MapConfig.new()).is_empty(),
		"Catalog is ready for the full pipeline"
	)

	var template := catalog.rules[0].placements[0]
	var copy := template.copy_at(Vector3i(3, 0, 5), 1)
	_check(
		copy.cell == Vector3i(3, 0, 5) and copy.quarter_turns == 1,
		"Placement copy has the new position and rotation"
	)
	_check(
		template.cell == Vector3i.ZERO and template.quarter_turns == 0, "Template remains unchanged"
	)

	var unverified := TileRule.new()
	unverified.rule_id = &"unverified"
	unverified.placements = [copy]
	unverified.enabled = true
	_check(not unverified.validate().is_empty(), "Unverified rules cannot be enabled")


func _test_data() -> void:
	var data := MapData.new()
	data.initialize(Vector2i(6, 6))
	_check(
		data.get_neighbors_4(Vector2i.ZERO).size() == 2,
		"Corner cells have no out-of-bounds neighbors"
	)
	_check(not data.is_walkable(Vector2i(-1, 0)), "Cells outside the map are not walkable")
	_check(
		data.can_traverse(Vector2i.ZERO, Vector2i.RIGHT), "Cells at the same height are traversable"
	)
	data.set_height(Vector2i.RIGHT, 1)
	_check(
		not data.can_traverse(Vector2i.ZERO, Vector2i.RIGHT),
		"Height differences block implicit traversal"
	)
	_check(not data.can_traverse(Vector2i.ZERO, Vector2i.ONE), "No implicit diagonal movement")

	var upper := Vector2i(3, 0)
	data.set_height(upper, 1)
	_check(data.add_connection(Vector2i.ZERO, upper), "Multi-cell stairs can be registered")
	_check(
		data.get_traversable_neighbors(Vector2i.ZERO).has(upper),
		"BFS includes non-adjacent stair endpoints"
	)
	_check(data.can_traverse(upper, Vector2i.ZERO), "Stairs are bidirectional by default")
	data.set_walkable(upper, false)
	_check(not data.can_traverse(Vector2i.ZERO, upper), "Blocked endpoints cannot be entered")
	_check(
		not data.reserve_area(Vector2i(5, 5), Vector2i(2, 2)),
		"Out-of-bounds reservations are rejected"
	)
	_check(not data.is_reserved(Vector2i(5, 5)), "Failed reservations leave no partial changes")
	_check(data.reserve_area(Vector2i.ONE, Vector2i(2, 2)), "Valid areas can be reserved")
	_check(data.is_reserved(Vector2i(2, 2)), "All cells in the area are reserved")
	data.set_terrain(Vector2i.ONE, MapData.Terrain.PATH)
	_check(data.get_terrain(Vector2i.ONE) == MapData.Terrain.PATH, "Terrain round trip")
	data.initialize(Vector2i(2, 2))
	_check(
		data.height_levels.size() == 4 and not data.is_reserved(Vector2i.ONE),
		"Initialization resets dimensions and reservations"
	)
	_check(
		data.start_cell == MapData.INVALID_CELL and data.stairs.is_empty(),
		"Initialization clears the previous generation state"
	)


func _test_scene_and_scripts() -> void:
	for path in [
		"layout_generator",
		"elevation_generator",
		"tile_resolver",
		"map_validator",
		"spawn_planner",
		"grid_map_builder"
	]:
		var script := load("res://scripts/procedural/%s.gd" % path) as Script
		_check(script != null and script.can_instantiate(), "Scaffold parses: " + path)

	var packed := load("res://scenes/procedural_map.tscn") as PackedScene
	_check(packed != null, "Procedural scene loads")
	if packed == null:
		return

	var scene := packed.instantiate()
	var controller := scene.get_node("MapGenerator") as MapGenerator
	_check(controller != null, "Controller is attached to the expected node type")
	if controller != null:
		_check(
			controller.validate_dependencies(false).is_empty(),
			"Scene wiring is ready for ground generation"
		)
		_check(
			controller.validate_dependencies(true).is_empty(),
			"Wiring is ready for the full pipeline"
		)

	scene.free()
