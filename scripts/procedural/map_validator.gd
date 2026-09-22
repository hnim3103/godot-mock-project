class_name MapValidator
extends RefCounted


func distances(data: MapData, start: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	if not data.is_walkable(start):
		return result

	var queue: Array[Vector2i] = [start]
	result[start] = 0

	var head := 0

	while head < queue.size():
		var cell := queue[head]
		head += 1

		for neighbor in data.get_traversable_neighbors(cell):
			if not result.has(neighbor):
				result[neighbor] = int(result[cell]) + 1
				queue.append(neighbor)

	return result


func shortest_path(data: MapData, start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var parents: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	if not data.is_walkable(start) or not data.is_walkable(target):
		return []

	while head < queue.size() and not parents.has(target):
		var cell := queue[head]
		head += 1

		for next in data.get_traversable_neighbors(cell):
			if not parents.has(next):
				parents[next] = cell
				queue.append(next)

	if not parents.has(target):
		return []

	var path: Array[Vector2i] = [target]

	while path.back() != start:
		path.append(parents[path.back()])

	path.reverse()

	return path


func validate(data: MapData, config: MapConfig) -> PackedStringArray:
	var errors := PackedStringArray()
	if data == null:
		return PackedStringArray(["No map data available."])

	var count := data.size.x * data.size.y
	if (
		data.size != config.map_size
		or data.terrain_types.size() != count
		or data.height_levels.size() != count
		or data.walkable_flags.size() != count
		or data.reserved_flags.size() != count
		or data.region_ids.size() != count
	):
		return PackedStringArray(["Data dimensions do not match the config."])

	var reachable := distances(data, data.start_cell)
	if not reachable.has(data.exit_cell):
		errors.append("No path from start to exit.")
	elif int(reachable[data.exit_cell]) < config.min_start_exit_distance:
		errors.append("Start and exit are too close together.")

	for z in range(data.size.y):
		for x in range(data.size.x):
			var cell := Vector2i(x, z)
			if data.get_height(cell) < 0 or data.get_height(cell) > config.max_height_level:
				errors.append("Height out of bounds: %s" % cell)

			if data.is_walkable(cell) and not reachable.has(cell):
				errors.append("Unreachable area: %s" % cell)

	for spawn in data.spawns:
		if not reachable.has(spawn.cell):
			errors.append("Unreachable spawn: %s" % spawn.cell)

	return errors


func flood_fill(data: MapData, start: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(distances(data, start).keys())

	return result


func validate_connectivity(data: MapData) -> bool:
	var reachable := distances(data, data.start_cell)
	if not reachable.has(data.exit_cell):
		return false

	for spawn in data.spawns:
		if not reachable.has(spawn.cell):
			return false

	return true


func validate_stairs(data: MapData, catalog: TileCatalog) -> PackedStringArray:
	var errors := PackedStringArray()

	for flight in data.stairs:
		if catalog.get_rule(flight.rule_id) == null:
			errors.append("Missing stair template: %s" % flight.rule_id)

		for i in range(2):
			if not data.can_traverse(flight.entrances[i], flight.exits[i]):
				errors.append("Stairs have no valid connection.")

			if (
				data.get_height(flight.exits[i]) - data.get_height(flight.entrances[i])
				!= flight.anchor.y
			):
				errors.append("Stair endpoint heights do not match.")

	return errors


func validate_placements(
	placements: Array[TilePlacement], data: MapData, catalog: TileCatalog
) -> PackedStringArray:
	var errors := PackedStringArray()
	var occupied: Dictionary = {}
	var floors: Dictionary = {}
	var stairs: Dictionary = {}

	for p in placements:
		if p == null:
			errors.append("Placement null.")
			continue

		errors.append_array(p.validate())

		var flat := Vector2i(p.cell.x, p.cell.z)
		if not data.is_in_bounds(flat) or p.cell.y < 0 or p.cell.y > data.get_height(flat) + 1:
			errors.append("Placement out of bounds: %s" % p.cell)
			continue

		if catalog.get_item_id(p.item_name) < 0:
			errors.append("Missing mesh: %s" % p.item_name)

		var key := "%s:%s" % [p.layer, p.cell]
		if occupied.has(key):
			errors.append("Duplicate placement: " + key)

		occupied[key] = true
		if p.layer == "ground":
			floors[flat] = true
			if data.stair_cells.has(flat) or p.cell != data.to_grid_cell(flat):
				errors.append("Ground surface is on the wrong level or overlaps stairs.")
		elif String(p.item_name).begins_with("stair_"):
			stairs[flat] = true

	for z in range(data.size.y):
		for x in range(data.size.x):
			var cell := Vector2i(x, z)
			if data.stair_cells.has(cell):
				if not stairs.has(cell):
					errors.append("Missing stair piece at %s" % cell)
			elif not floors.has(cell):
				errors.append("Missing ground surface at %s" % cell)

	return errors
