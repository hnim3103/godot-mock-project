class_name MapConfig
extends Resource
## Map generation configuration. Do not store per-generation state in this Resource.

@export_group("Map")
## Logical dimensions (X, Z), measured in cells.
@export var map_size: Vector2i = Vector2i(32, 32)
## Outer border excluded from main path and spawn placement.
@export_range(0, 64, 1) var border_margin: int = 2

@export_group("Seed")
## 0 is a valid seed. The controller owns the actual seed; do not modify the preset.
@export var seed_value: int = 12345
## The controller reads this flag only when the user requests initial generation.
@export var randomize_seed: bool = false
## Store alongside the seed when saving/reproducing maps; increment when the algorithm changes.
@export var generator_version: String = "1"
@export_range(1, 100, 1) var max_generation_attempts: int = 8

@export_group("Paths")
## Path width in cells; must accommodate the character footprint.
@export_range(1, 32, 1) var path_width: int = 2
@export_range(0, 64, 1) var waypoint_count: int = 4
@export_range(0, 64, 1) var branch_count: int = 3
## Branch length range; the generator determines how to create and validate branches.
@export var branch_length_range: Vector2i = Vector2i(3, 8)

@export_group("Spawns")
## Radius in cells; the safe area is a (2r + 1) × (2r + 1) square.
@export_range(0, 32, 1) var spawn_safe_radius: int = 2
## Minimum distance in path steps, not world units.
@export_range(1, 4096, 1) var min_start_exit_distance: int = 12
@export_range(0, 256, 1) var enemy_spawn_count: int = 0
@export_range(0, 256, 1) var item_spawn_count: int = 0
@export_range(1, 128, 1) var min_spawn_spacing: int = 3

@export_group("Elevation")
@export var enable_elevation: bool = false
## Target plateau count; smaller maps may place fewer to preserve paths.
@export_range(0, 16, 1) var plateau_count: int = 3
@export_range(0, 16, 1) var max_height_level: int = 2
## Minimum plateau dimensions on X/Z.
@export var min_plateau_size: Vector2i = Vector2i(4, 4)
## Allow plateaus to intersect the main path; recompute the debug route on the graph after placing stairs.
@export var allow_main_path_elevation: bool = false

@export_group("Grid Geometry")
## One height_level equals cell_size.y world units at scale = 1.
@export var cell_size: Vector3 = Vector3(2.0, 2.0, 2.0)
## Apply the same convention to all GridMaps in the map.
@export var center_cells: Vector3i = Vector3i(1, 1, 1)
## The existing ground surface is at local Y = 1 relative to the item origin.
@export var ground_surface_offset: Vector3 = Vector3(0.0, 1.0, 0.0)

@export_group("Build")
## Placements per frame if the builder uses batching.
@export_range(1, 65536, 1) var build_batch_size: int = 512
## The procedural library includes collision; enable to reject catalogs with missing shapes after asset edits.
@export var require_collision: bool = false


func get_interior_rect() -> Rect2i:
	return Rect2i(
		Vector2i(border_margin, border_margin), map_size - Vector2i.ONE * border_margin * 2
	)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if map_size.x <= 0 or map_size.y <= 0:
		errors.append("map_size must be positive on both X and Z.")

	if border_margin < 0:
		errors.append("border_margin must not be negative.")

	var interior := get_interior_rect().size
	if interior.x <= 0 or interior.y <= 0:
		errors.append("border_margin leaves no interior area in the map.")

	if path_width < 1 or path_width > mini(interior.x, interior.y):
		errors.append("path_width must be >= 1 and fit inside the map interior.")

	if waypoint_count < 0 or branch_count < 0:
		errors.append("waypoint_count and branch_count must not be negative.")

	if branch_length_range.x < 1 or branch_length_range.y < branch_length_range.x:
		errors.append("branch_length_range must satisfy 1 <= min <= max.")

	if spawn_safe_radius < 0 or 2 * spawn_safe_radius + 1 > mini(interior.x, interior.y):
		errors.append("The safe spawn area must fit inside the map interior.")

	if min_start_exit_distance < 1 or min_start_exit_distance >= interior.x * interior.y:
		errors.append(
			"min_start_exit_distance must be positive and less than the number of interior cells."
		)

	if enemy_spawn_count < 0 or item_spawn_count < 0 or min_spawn_spacing < 1:
		errors.append("Spawn counts must be nonnegative and min_spawn_spacing must be >= 1.")

	if max_height_level < 0 or (enable_elevation and max_height_level < 1):
		errors.append("max_height_level must be >= 0, or >= 1 when elevation is enabled.")

	if plateau_count < 0:
		errors.append("plateau_count must not be negative.")

	if (
		enable_elevation
		and (
			min_plateau_size.x < 1
			or min_plateau_size.y < 1
			or min_plateau_size.x > interior.x
			or min_plateau_size.y > interior.y
		)
	):
		errors.append("min_plateau_size must be positive and fit inside the map interior.")

	if allow_main_path_elevation and not enable_elevation:
		errors.append("allow_main_path_elevation requires enable_elevation.")

	if not cell_size.is_finite() or cell_size.x <= 0.0 or cell_size.y <= 0.0 or cell_size.z <= 0.0:
		errors.append("cell_size must be finite and positive on all three axes.")

	if center_cells.x not in [0, 1] or center_cells.y not in [0, 1] or center_cells.z not in [0, 1]:
		errors.append("center_cells only accepts 0 or 1 on each axis.")

	if not ground_surface_offset.is_finite():
		errors.append("ground_surface_offset must be finite.")

	if max_generation_attempts < 1 or build_batch_size < 1:
		errors.append("max_generation_attempts and build_batch_size must be >= 1.")

	if generator_version.strip_edges().is_empty():
		errors.append("generator_version must not be empty.")

	return errors
