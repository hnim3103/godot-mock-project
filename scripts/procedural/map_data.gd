class_name MapData
extends RefCounted
## Data for one map generation. Does not store mesh IDs, Nodes or catalog Resources.
## Each X/Z cell has one walkable surface; caves/bridges with overlapping levels are not supported yet.

enum Terrain { GROUND, PATH }

const INVALID_CELL := Vector2i(-1, -1)
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var size: Vector2i = Vector2i.ZERO
var used_seed: int = 0
var attempt_index: int = 0
var generator_version: String = ""
var catalog_version: String = ""

var terrain_types := PackedInt32Array()
var height_levels := PackedInt32Array()
var walkable_flags := PackedByteArray()
var reserved_flags := PackedByteArray()
var region_ids := PackedInt32Array()

var start_cell: Vector2i = INVALID_CELL
var exit_cell: Vector2i = INVALID_CELL
var main_path: Array[Vector2i] = []

## Flight: rule_id, anchor (top level), quarter_turns, plateau,
## entrances/exits (two endpoints for two lanes). Ramp segment count = anchor.y.
var stairs: Array[Dictionary] = []
var stair_cells: Dictionary = {}
var plateaus: Array[Rect2i] = []

## Schema: {"kind": StringName (player/exit/enemy/item), "cell": Vector2i}.
var spawns: Array[Dictionary] = []

## Explicit traversal edges registered by the elevation generator after placing stairs.
var _connections: Dictionary = {}


func initialize(map_size: Vector2i) -> void:
	assert(map_size.x > 0 and map_size.y > 0, "MapData requires positive dimensions.")
	size = map_size

	var count := size.x * size.y
	terrain_types.resize(count)
	terrain_types.fill(Terrain.GROUND)

	height_levels.resize(count)
	height_levels.fill(0)

	walkable_flags.resize(count)
	walkable_flags.fill(1)

	reserved_flags.resize(count)
	reserved_flags.fill(0)

	region_ids.resize(count)
	region_ids.fill(-1)

	start_cell = INVALID_CELL
	exit_cell = INVALID_CELL
	main_path.clear()
	stairs.clear()
	stair_cells.clear()
	plateaus.clear()
	spawns.clear()
	_connections.clear()

	used_seed = 0
	attempt_index = 0
	generator_version = ""
	catalog_version = ""


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func get_index(cell: Vector2i) -> int:
	assert(is_in_bounds(cell), "Cell is outside the map: %s" % cell)
	return cell.x + cell.y * size.x


func get_neighbors_4(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_in_bounds(cell):
		return result

	for direction in CARDINALS:
		var neighbor := cell + direction
		if is_in_bounds(neighbor):
			result.append(neighbor)

	return result


func get_height(cell: Vector2i) -> int:
	return height_levels[get_index(cell)]


func set_height(cell: Vector2i, level: int) -> void:
	assert(level >= 0, "Negative heights are not supported yet.")
	height_levels[get_index(cell)] = level


func get_terrain(cell: Vector2i) -> Terrain:
	return terrain_types[get_index(cell)] as Terrain


func set_terrain(cell: Vector2i, terrain: Terrain) -> void:
	terrain_types[get_index(cell)] = terrain


func is_walkable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and walkable_flags[get_index(cell)] != 0


func set_walkable(cell: Vector2i, value: bool) -> void:
	walkable_flags[get_index(cell)] = int(value)


func is_reserved(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and reserved_flags[get_index(cell)] != 0


func reserve_area(origin: Vector2i, area_size: Vector2i) -> bool:
	# Reject the entire out-of-bounds area; do not reserve part of it and report success.
	if area_size.x <= 0 or area_size.y <= 0:
		return false

	if not is_in_bounds(origin) or not is_in_bounds(origin + area_size - Vector2i.ONE):
		return false

	for z in range(origin.y, origin.y + area_size.y):
		for x in range(origin.x, origin.x + area_size.x):
			reserved_flags[get_index(Vector2i(x, z))] = 1

	return true


func add_connection(from: Vector2i, to: Vector2i, bidirectional: bool = true) -> bool:
	# The caller must verify the stair footprint and actual geometry.
	if from == to or not is_walkable(from) or not is_walkable(to):
		return false

	_add_directed_connection(from, to)
	if bidirectional:
		_add_directed_connection(to, from)

	return true


func _add_directed_connection(from: Vector2i, to: Vector2i) -> void:
	if not _connections.has(from):
		_connections[from] = []

	if not _connections[from].has(to):
		_connections[from].append(to)


func can_traverse(from: Vector2i, to: Vector2i) -> bool:
	if from == to or not is_walkable(from) or not is_walkable(to):
		return false

	if _connections.has(from) and _connections[from].has(to):
		return true

	var delta := to - from

	return absi(delta.x) + absi(delta.y) == 1 and get_height(from) == get_height(to)


func get_traversable_neighbors(cell: Vector2i) -> Array[Vector2i]:
	# BFS must use this function to include multi-cell stairs with non-adjacent endpoints.
	var candidates := get_neighbors_4(cell)
	if _connections.has(cell):
		for target: Vector2i in _connections[cell]:
			if not candidates.has(target):
				candidates.append(target)

	var result: Array[Vector2i] = []

	for neighbor in candidates:
		if can_traverse(cell, neighbor):
			result.append(neighbor)

	return result


func to_grid_cell(cell: Vector2i) -> Vector3i:
	return Vector3i(cell.x, get_height(cell), cell.y)
