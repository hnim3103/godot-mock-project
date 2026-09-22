class_name SpawnPlanner
extends RefCounted


func plan(data: MapData, config: MapConfig, rng: RandomNumberGenerator) -> bool:
	data.spawns.clear()
	data.spawns.append({"kind": &"player", "cell": data.start_cell})
	data.spawns.append({"kind": &"exit", "cell": data.exit_cell})

	var candidates := collect_candidates(data, config)

	# Fisher-Yates with this stage's RNG, never Array.shuffle/global RNG.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = temp

	var validator := MapValidator.new()
	var excluded: Dictionary = {}

	for endpoint in [data.start_cell, data.exit_cell]:
		var distances := validator.distances(data, endpoint)

		for cell in distances:
			if int(distances[cell]) < maxi(config.spawn_safe_radius + 1, config.min_spawn_spacing):
				excluded[cell] = true

	var needed := config.enemy_spawn_count + config.item_spawn_count
	var placed := 0

	for candidate in candidates:
		if placed >= needed:
			break

		if excluded.has(candidate):
			continue

		data.spawns.append(
			{"kind": &"enemy" if placed < config.enemy_spawn_count else &"item", "cell": candidate}
		)
		placed += 1

		var distances := validator.distances(data, candidate)

		for cell in distances:
			if int(distances[cell]) < config.min_spawn_spacing:
				excluded[cell] = true

	return placed == needed


func collect_candidates(data: MapData, _config: MapConfig) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var reachable := MapValidator.new().distances(data, data.start_cell)

	for z in range(data.size.y):
		for x in range(data.size.x):
			var cell := Vector2i(x, z)
			if reachable.has(cell) and not data.is_reserved(cell) and is_spawn_valid(data, cell, 1):
				result.append(cell)

	return result


func is_spawn_valid(data: MapData, cell: Vector2i, clearance: int) -> bool:
	if not data.is_walkable(cell):
		return false

	for z in range(-clearance, clearance + 1):
		for x in range(-clearance, clearance + 1):
			var neighbor := cell + Vector2i(x, z)
			if not data.is_walkable(neighbor) or data.get_height(neighbor) != data.get_height(cell):
				return false

	return true
