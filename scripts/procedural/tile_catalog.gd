class_name TileCatalog
extends Resource
## The catalog stores templates, not generated results. Lookups are rebuilt before validation.

@export var mesh_library: MeshLibrary
@export var catalog_version: String = "1"
@export var rules: Array[TileRule] = []

var _item_ids: Dictionary = {}


func get_rule(id: StringName) -> TileRule:
	for rule in rules:
		if rule != null and rule.rule_id == id and rule.enabled and rule.verified:
			return rule

	return null


func build_item_lookup() -> void:
	_item_ids.clear()
	if mesh_library == null:
		return

	for item_id in mesh_library.get_item_list():
		_item_ids[StringName(mesh_library.get_item_name(item_id))] = item_id


func get_item_id(item_name: StringName) -> int:
	# Query the current resource to avoid stale IDs after the library is re-exported.
	if mesh_library == null:
		return GridMap.INVALID_CELL_ITEM

	return mesh_library.find_item_by_name(String(item_name))


func get_rules(group: TileRule.Group, only_enabled: bool = true) -> Array[TileRule]:
	var result: Array[TileRule] = []

	for rule in rules:
		if rule != null and rule.group == group:
			if not only_enabled or (rule.enabled and rule.verified):
				result.append(rule)

	return result


func validate_library(require_collision: bool = false) -> PackedStringArray:
	var errors := PackedStringArray()
	build_item_lookup()
	if mesh_library == null:
		errors.append("Catalog has no MeshLibrary.")
		return errors

	if catalog_version.strip_edges().is_empty():
		errors.append("catalog_version must not be empty.")

	var names: Dictionary = {}

	for item_id in mesh_library.get_item_list():
		var item_name := mesh_library.get_item_name(item_id)
		if item_name.is_empty() or names.has(item_name):
			errors.append("MeshLibrary contains an empty or duplicate name: " + item_name)

		names[item_name] = true

	var ids: Dictionary = {}

	for rule in rules:
		if rule == null:
			errors.append("Catalog contains a null rule.")
			continue

		if ids.has(rule.rule_id):
			errors.append("Duplicate rule_id: " + String(rule.rule_id))

		ids[rule.rule_id] = true

		for error in rule.validate():
			errors.append("%s: %s" % [rule.rule_id, error])

		for placement in rule.placements:
			if placement == null:
				continue

			var item_id := get_item_id(placement.item_name)
			if item_id == GridMap.INVALID_CELL_ITEM:
				errors.append("%s: missing mesh %s." % [rule.rule_id, placement.item_name])
				continue

			if mesh_library.get_item_mesh(item_id) == null:
				errors.append("%s: item has no mesh." % placement.item_name)

			if (
				require_collision
				and rule.enabled
				and mesh_library.get_item_shapes(item_id).is_empty()
			):
				errors.append("%s: missing collision." % placement.item_name)

	if get_rules(TileRule.Group.GROUND).is_empty():
		errors.append("Catalog requires at least one enabled and verified GROUND rule.")

	return errors


func validate_for_config(config: MapConfig) -> PackedStringArray:
	if config == null:
		return PackedStringArray(["Missing MapConfig."])

	var errors := validate_library(config.require_collision)
	if (
		not config.cell_size.is_equal_approx(Vector3(2, 2, 2))
		or not config.ground_surface_offset.is_equal_approx(Vector3(0, 1, 0))
	):
		errors.append(
			"The forest library requires cell_size=(2,2,2) and ground_surface_offset=(0,1,0)."
		)

	if get_rules(TileRule.Group.PATH).is_empty():
		errors.append(
			"No verified PATH rule available; only ground generation is currently supported."
		)

	if config.enable_elevation:
		if get_rules(TileRule.Group.WALL).is_empty():
			errors.append("Elevation requires a verified WALL rule.")

		if get_rules(TileRule.Group.STAIRS).is_empty():
			errors.append("Elevation requires a verified STAIRS template.")

	return errors
