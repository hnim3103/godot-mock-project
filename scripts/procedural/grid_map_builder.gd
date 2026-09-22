class_name GridMapBuilder
extends RefCounted


func build(
	placements: Array[TilePlacement],
	catalog: TileCatalog,
	config: MapConfig,
	ground: GridMap,
	structures: GridMap
) -> bool:
	if ground == null or structures == null or ground == structures:
		return false

	for p in placements:
		if p == null or not p.validate().is_empty() or catalog.get_item_id(p.item_name) < 0:
			return false

	# No mutations until every placement passed the preflight above.
	clear_map(ground, structures)

	for grid in [ground, structures]:
		grid.mesh_library = catalog.mesh_library
		grid.cell_size = config.cell_size
		grid.cell_center_x = config.center_cells.x != 0
		grid.cell_center_y = config.center_cells.y != 0
		grid.cell_center_z = config.center_cells.z != 0
		grid.collision_layer = 1
		grid.collision_mask = 1
		grid.bake_navigation = false

	for p in placements:
		var grid := ground if p.layer == "ground" else structures
		grid.set_cell_item(
			p.cell, catalog.get_item_id(p.item_name), get_orientation(grid, p.quarter_turns)
		)

	return true


func clear_map(ground: GridMap, structures: GridMap) -> void:
	ground.clear()
	structures.clear()


func get_orientation(grid: GridMap, quarter_turns: int) -> int:
	return grid.get_orthogonal_index_from_basis(
		Basis(Vector3.UP, posmod(quarter_turns, 4) * PI / 2.0)
	)


func cell_to_world(grid: GridMap, cell: Vector3i, surface_offset: Vector3) -> Vector3:
	return grid.to_global(grid.map_to_local(cell) + surface_offset)


func world_to_cell(grid: GridMap, position: Vector3) -> Vector3i:
	return grid.local_to_map(grid.to_local(position))
