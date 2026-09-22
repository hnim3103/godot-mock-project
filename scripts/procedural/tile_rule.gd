class_name TileRule
extends Resource
## Rule data; the resolver handles neighbor matching, footprint rotation and weighted selection.
## Base orientation: North = -Z, East = +X, South = +Z, West = -X.

enum Group { GROUND, PATH, WALL, STAIRS }

@export var rule_id: StringName = &""
@export var group: Group = Group.GROUND
## Disabled rules still have their mesh names validated, but are not used by the resolver.
@export var enabled: bool = false
## Enable only after previewing connections in the base orientation and all allowed_rotations.
@export var verified: bool = false
@export_multiline var notes: String = ""
@export_range(0.001, 1000.0) var weight: float = 1.0
@export var allowed_rotations: PackedInt32Array = PackedInt32Array([0])

@export_group("Neighbors")
## -1: ignored; 0..15: exact mask in the template's base orientation.
@export_range(-1, 15, 1) var neighbor_mask: int = -1
## -1: ignored. NE=1, SE=2, SW=4, NW=8.
@export_range(-1, 15, 1) var diagonal_mask: int = -1
## Height differences (neighbor - current) in N/E/S/W order; 999 means ignored.
@export var neighbor_height_deltas: PackedInt32Array = PackedInt32Array([999, 999, 999, 999])

@export_group("Template")
@export var placements: Array[TilePlacement] = []
## Logical X/Z footprint cells to keep clear/reserve, relative to the anchor.
@export var occupied_cells: Array[Vector2i] = [Vector2i.ZERO]
@export var surface_offset: Vector3 = Vector3(0.0, 1.0, 0.0)

@export_group("Stair Connection")
## Endpoint offsets relative to the anchor; Vector3i uses (x, height_level, z).
@export var entrance_offset: Vector3i = Vector3i.ZERO
@export var exit_offset: Vector3i = Vector3i.ZERO
## Integer height difference from entrance to exit.
@export var height_delta: int = 0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if rule_id == &"":
		errors.append("rule_id must not be empty.")

	if group < Group.GROUND or group > Group.STAIRS:
		errors.append("Invalid group.")

	if enabled and not verified:
		errors.append("Rule is enabled but has not been verified.")

	if not is_finite(weight) or weight <= 0.0:
		errors.append("weight must be finite and > 0.")

	if allowed_rotations.is_empty():
		errors.append("allowed_rotations must not be empty.")

	var seen_rotations: Dictionary = {}

	for turn in allowed_rotations:
		if turn < 0 or turn > 3 or seen_rotations.has(turn):
			errors.append("allowed_rotations must contain unique values in 0..3.")

		seen_rotations[turn] = true

	if neighbor_mask < -1 or neighbor_mask > 15 or diagonal_mask < -1 or diagonal_mask > 15:
		errors.append("Neighbor mask must be in -1..15.")

	if neighbor_height_deltas.size() != 4:
		errors.append("neighbor_height_deltas requires exactly 4 entries in N/E/S/W order.")

	if placements.is_empty() or occupied_cells.is_empty():
		errors.append("Template requires placements and occupied_cells.")

	var seen_cells: Dictionary = {}

	for placement in placements:
		if placement == null:
			errors.append("Template contains a null placement.")
			continue

		for error in placement.validate():
			errors.append(error)

		var key := "%s:%s" % [placement.layer, placement.cell]
		if seen_cells.has(key):
			errors.append("Two placements share a cell/layer in the same template: " + key)

		seen_cells[key] = true

	if not surface_offset.is_finite():
		errors.append("surface_offset must be finite.")

	if enabled and group == Group.STAIRS:
		if height_delta == 0 or exit_offset.y - entrance_offset.y != height_delta:
			errors.append(
				"Stair templates require a nonzero height_delta matching their endpoints."
			)

		if Vector2i(entrance_offset.x, entrance_offset.z) == Vector2i(exit_offset.x, exit_offset.z):
			errors.append("The heightmap model requires stair endpoints in different X/Z cells.")

	return errors
