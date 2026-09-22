class_name TileResolver
extends RefCounted

var errors := PackedStringArray()
var _rules: Dictionary = {}


func resolve(
	data: MapData, catalog: TileCatalog, rng: RandomNumberGenerator
) -> Array[TilePlacement]:
	errors.clear()
	_rules.clear()

	for rule in catalog.rules:
		if rule.enabled and rule.verified:
			_rules[rule.rule_id] = rule

	var result: Array[TilePlacement] = []

	for z in range(data.size.y):
		for x in range(data.size.x):
			var cell := Vector2i(x, z)
			if data.stair_cells.has(cell):
				continue

			if data.get_terrain(cell) == MapData.Terrain.PATH:
				result.append_array(resolve_path(data, cell, catalog, rng))
			else:
				result.append_array(resolve_ground(data, cell, catalog, rng))

			result.append_array(resolve_walls(data, cell, catalog))

	result.append_array(resolve_stairs(data, catalog))

	return result if errors.is_empty() else []


func _same(data: MapData, cell: Vector2i, neighbor: Vector2i) -> bool:
	return (
		data.is_walkable(neighbor)
		and data.get_height(cell) == data.get_height(neighbor)
		and data.get_terrain(cell) == data.get_terrain(neighbor)
	)


func get_neighbor_mask(data: MapData, cell: Vector2i) -> int:
	var mask := 0

	for i in range(4):
		if _same(data, cell, cell + MapData.CARDINALS[i]):
			mask |= 1 << i

	return mask


func get_diagonal_mask(data: MapData, cell: Vector2i) -> int:
	var mask := 0
	var diagonals := [Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

	for i in range(4):
		if _same(data, cell, cell + diagonals[i]):
			mask |= 1 << i

	return mask


func resolve_ground(
	data: MapData, cell: Vector2i, catalog: TileCatalog, rng: RandomNumberGenerator
) -> Array[TilePlacement]:
	var rules := catalog.get_rules(TileRule.Group.GROUND)
	var total := 0.0

	for rule in rules:
		total += rule.weight

	var choice := rng.randf() * total

	for rule in rules:
		choice -= rule.weight
		if choice <= 0.0:
			return _expand(
				rule,
				data.to_grid_cell(cell),
				rule.allowed_rotations[rng.randi_range(0, rule.allowed_rotations.size() - 1)]
			)

	errors.append("No ground rule available.")

	return []


func resolve_path(
	data: MapData, cell: Vector2i, catalog: TileCatalog, _rng: RandomNumberGenerator
) -> Array[TilePlacement]:
	var id := StringName(
		"path_%02d_%02d" % [get_neighbor_mask(data, cell), get_diagonal_mask(data, cell)]
	)
	var rule: TileRule = _rules.get(id, catalog.get_rule(id))
	if rule == null:
		errors.append("Missing path rule " + String(id))
		return []

	return _expand(rule, data.to_grid_cell(cell), 0)


func resolve_walls(data: MapData, cell: Vector2i, catalog: TileCatalog) -> Array[TilePlacement]:
	var result: Array[TilePlacement] = []

	for level in range(data.get_height(cell) + 1):
		var mask := 0

		for i in range(4):
			var neighbor := cell + MapData.CARDINALS[i]
			var low := -1
			if data.is_in_bounds(neighbor):
				low = data.get_height(neighbor)
				if data.stair_cells.has(neighbor):
					low = int(data.stair_cells[neighbor].level)

			if level > low:
				mask |= 1 << i

		if mask == 0:
			continue

		var id := StringName("cliff_%02d" % mask)
		var rule: TileRule = _rules.get(id, catalog.get_rule(id))
		if rule == null:
			errors.append("Missing wall rule " + String(id))
		else:
			result.append_array(_expand(rule, Vector3i(cell.x, level, cell.y), 0))

	return result


func resolve_stairs(data: MapData, catalog: TileCatalog) -> Array[TilePlacement]:
	var result: Array[TilePlacement] = []

	for flight in data.stairs:
		var rule := catalog.get_rule(flight.rule_id)
		if rule == null:
			errors.append("Missing stair template " + String(flight.rule_id))
			continue

		var anchor: Vector3i = flight.anchor

		for row in range(anchor.y):
			var at := (
				anchor + ElevationGenerator.rotate3(Vector3i(0, -row, row), flight.quarter_turns)
			)
			result.append_array(_expand(rule, at, flight.quarter_turns))

	return result


func _expand(rule: TileRule, anchor: Vector3i, turns: int) -> Array[TilePlacement]:
	var result: Array[TilePlacement] = []

	for placement in rule.placements:
		result.append(
			placement.copy_at(anchor + ElevationGenerator.rotate3(placement.cell, turns), turns)
		)

	return result
