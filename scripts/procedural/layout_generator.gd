class_name LayoutGenerator
extends RefCounted


func generate(config: MapConfig, rng: RandomNumberGenerator) -> MapData:
	if not config.validate().is_empty():
		return null

	var data := MapData.new()
	data.initialize(config.map_size)
	if not choose_endpoints(data, config, rng):
		return null

	var points := generate_waypoints(data, config, rng)
	if not carve_path(data, points, config.path_width, rng):
		return null

	if not reserve_spawn_zones(data, config.spawn_safe_radius):
		return null

	add_branches(data, config, rng)

	return data


func choose_endpoints(data: MapData, config: MapConfig, rng: RandomNumberGenerator) -> bool:
	var padding := maxi(config.spawn_safe_radius, ceili(config.path_width / 2.0))
	var rect := config.get_interior_rect().grow(-padding)
	if not rect.has_area():
		return false

	if data.size.y >= data.size.x:
		data.start_cell = Vector2i(rng.randi_range(rect.position.x, rect.end.x - 1), rect.end.y - 1)
		data.exit_cell = Vector2i(rng.randi_range(rect.position.x, rect.end.x - 1), rect.position.y)
	else:
		data.start_cell = Vector2i(
			rect.position.x, rng.randi_range(rect.position.y, rect.end.y - 1)
		)
		data.exit_cell = Vector2i(rect.end.x - 1, rng.randi_range(rect.position.y, rect.end.y - 1))

	return data.start_cell != data.exit_cell


func generate_waypoints(
	data: MapData, config: MapConfig, rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var points: Array[Vector2i] = [data.start_cell]
	var rect := config.get_interior_rect().grow(-ceili(config.path_width / 2.0))

	for i in range(config.waypoint_count):
		var t := float(i + 1) / float(config.waypoint_count + 1)
		var cell := Vector2i(Vector2(data.start_cell).lerp(Vector2(data.exit_cell), t).round())
		if data.size.y >= data.size.x:
			cell.x = rng.randi_range(rect.position.x, rect.end.x - 1)
		else:
			cell.y = rng.randi_range(rect.position.y, rect.end.y - 1)

		if cell != points.back():
			points.append(cell)

	points.append(data.exit_cell)

	return points


func carve_path(
	data: MapData,
	points: Array[Vector2i],
	width: int,
	rng: RandomNumberGenerator,
	is_main_path: bool = true
) -> bool:
	if points.is_empty() or width < 1:
		return false

	var route: Array[Vector2i] = [points[0]]

	for i in range(1, points.size()):
		var current: Vector2i = route.back()
		var target := points[i]
		var axes := [0, 1] if rng.randi_range(0, 1) == 0 else [1, 0]

		for axis in axes:
			while current[axis] != target[axis]:
				current[axis] += signi(target[axis] - current[axis])
				route.append(current)

	var offset := -floori((width - 1) / 2.0)

	for cell in route:
		for z in range(offset, offset + width):
			for x in range(offset, offset + width):
				if not data.is_in_bounds(cell + Vector2i(x, z)):
					return false

	for cell in route:
		for z in range(offset, offset + width):
			for x in range(offset, offset + width):
				var painted := cell + Vector2i(x, z)
				data.set_terrain(painted, MapData.Terrain.PATH)
				data.reserve_area(painted, Vector2i.ONE)

	if is_main_path:
		data.main_path = route

	return true


func add_branches(data: MapData, config: MapConfig, rng: RandomNumberGenerator) -> bool:
	if data.main_path.is_empty():
		return false

	var rect := config.get_interior_rect().grow(-ceili(config.path_width / 2.0))

	for unused in range(config.branch_count):
		var start: Vector2i = data.main_path[rng.randi_range(0, data.main_path.size() - 1)]
		var direction: Vector2i = MapData.CARDINALS[rng.randi_range(0, 3)]
		var target := (
			start
			+ (
				direction
				* rng.randi_range(config.branch_length_range.x, config.branch_length_range.y)
			)
		)
		target = target.clamp(rect.position, rect.end - Vector2i.ONE)
		carve_path(data, [start, target], config.path_width, rng, false)

	return true


func reserve_spawn_zones(data: MapData, radius: int) -> bool:
	for cell in [data.start_cell, data.exit_cell]:
		if not data.reserve_area(cell - Vector2i.ONE * radius, Vector2i.ONE * (radius * 2 + 1)):
			return false

	return true
