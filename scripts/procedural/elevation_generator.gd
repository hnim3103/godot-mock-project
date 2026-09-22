class_name ElevationGenerator
extends RefCounted
## Rectangular plateaus with complete two-lane stair flights. All elevations remain reachable.


static func rotate2(value: Vector2i, turns: int) -> Vector2i:
	var result := value

	for unused in range(posmod(turns, 4)):
		result = Vector2i(result.y, -result.x)

	return result


static func rotate3(value: Vector3i, turns: int) -> Vector3i:
	var flat := rotate2(Vector2i(value.x, value.z), turns)
	return Vector3i(flat.x, value.y, flat.y)


func apply(
	data: MapData, config: MapConfig, catalog: TileCatalog, rng: RandomNumberGenerator
) -> bool:
	if not config.enable_elevation:
		return true

	if catalog.get_rules(TileRule.Group.STAIRS).is_empty():
		return false

	# Placement is transactional: inspect plateau and whole flight before changing any cells.
	for unused in range(config.plateau_count * 100):
		if data.plateaus.size() >= config.plateau_count:
			break

		var rect := config.get_interior_rect()
		var width := rng.randi_range(config.min_plateau_size.x, config.min_plateau_size.x + 3)
		var depth := rng.randi_range(config.min_plateau_size.y, config.min_plateau_size.y + 3)
		if width >= rect.size.x or depth >= rect.size.y:
			continue

		var plateau := Rect2i(
			Vector2i(
				rng.randi_range(rect.position.x, rect.end.x - width),
				rng.randi_range(rect.position.y, rect.end.y - depth)
			),
			Vector2i(width, depth)
		)
		var turns := rng.randi_range(0, 3)
		var anchor := Vector2i.ZERO

		match turns:
			0:
				anchor = Vector2i(plateau.position.x + 1, plateau.end.y)
			1:
				anchor = Vector2i(plateau.end.x, plateau.end.y - 2)
			2:
				anchor = Vector2i(plateau.end.x - 2, plateau.position.y - 1)
			3:
				anchor = Vector2i(plateau.position.x - 1, plateau.position.y + 1)

		var candidate := {
			"rule_id": &"stairs_pair",
			"anchor": Vector3i(anchor.x, rng.randi_range(1, config.max_height_level), anchor.y),
			"quarter_turns": turns,
			"plateau": plateau
		}
		if _can_place_plateau(data, plateau, config) and can_place_stair(data, candidate, catalog):
			for z in range(plateau.position.y, plateau.end.y):
				for x in range(plateau.position.x, plateau.end.x):
					var cell := Vector2i(x, z)
					data.set_height(cell, candidate.anchor.y)
					data.region_ids[data.get_index(cell)] = data.plateaus.size()

			data.plateaus.append(plateau)
			place_stair(data, candidate, catalog)

	# Density is a target; small/constrained maps may contain fewer plateaus.
	return not data.plateaus.is_empty() or config.plateau_count == 0


func _can_place_plateau(data: MapData, rect: Rect2i, config: MapConfig) -> bool:
	for other in data.plateaus:
		if rect.grow(config.max_height_level + 2).intersects(other):
			return false

	for z in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			var cell := Vector2i(x, z)
			if (
				not data.is_in_bounds(cell)
				or data.get_height(cell) != 0
				or data.stair_cells.has(cell)
			):
				return false

			if data.is_reserved(cell) and not config.allow_main_path_elevation:
				return false

			for spawn in [data.start_cell, data.exit_cell]:
				var delta: Vector2i = (cell - spawn).abs()
				if maxi(delta.x, delta.y) <= config.spawn_safe_radius + 1:
					return false

	return true


func can_place_stair(data: MapData, candidate: Dictionary, _catalog: TileCatalog) -> bool:
	var anchor: Vector3i = candidate.anchor
	var origin := Vector2i(anchor.x, anchor.z)
	var turns: int = candidate.quarter_turns

	for row in range(anchor.y + 1):
		for lane in range(2):
			var cell := origin + rotate2(Vector2i(lane, row), turns)
			if (
				not data.is_in_bounds(cell)
				or data.get_height(cell) != 0
				or data.is_reserved(cell)
				or data.stair_cells.has(cell)
			):
				return false

	return true


func place_stair(data: MapData, candidate: Dictionary, _catalog: TileCatalog) -> bool:
	var anchor: Vector3i = candidate.anchor
	var origin := Vector2i(anchor.x, anchor.z)
	var turns: int = candidate.quarter_turns
	var flight := candidate.duplicate()
	var entrances: Array[Vector2i] = []
	var exits: Array[Vector2i] = []

	for lane in range(2):
		var bottom := origin + rotate2(Vector2i(lane, anchor.y), turns)
		var top := origin + rotate2(Vector2i(lane, -1), turns)
		entrances.append(bottom)
		exits.append(top)
		data.add_connection(bottom, top)
		data.reserve_area(bottom, Vector2i.ONE)
		data.reserve_area(top, Vector2i.ONE)

		for row in range(anchor.y):
			var cell := origin + rotate2(Vector2i(lane, row), turns)
			data.stair_cells[cell] = {"level": anchor.y - row, "turns": turns}
			data.set_height(cell, anchor.y - row - 1)
			data.set_walkable(cell, false)
			data.reserve_area(cell, Vector2i.ONE)

	flight.entrances = entrances
	flight.exits = exits
	data.stairs.append(flight)

	return true
