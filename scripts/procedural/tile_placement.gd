class_name TilePlacement
extends Resource
## Used in TileRule templates and the resolver's result list.
## In templates, cell is an offset; after resolution, it is an absolute position.
## Do not modify catalog Resources during resolution: use copy_at().

@export_enum("ground", "structures") var layer: String = "ground"
@export var cell: Vector3i = Vector3i.ZERO
@export var item_name: StringName = &""
## Number of 90-degree turns around +Y; the builder converts this to a GridMap orientation.
@export_range(0, 3, 1) var quarter_turns: int = 0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if layer not in ["ground", "structures"]:
		errors.append("layer must be ground or structures.")

	if item_name == &"":
		errors.append("item_name must not be empty.")

	if quarter_turns < 0 or quarter_turns > 3:
		errors.append("quarter_turns must be in 0..3.")

	return errors


func copy_at(absolute_cell: Vector3i, additional_turns: int = 0) -> TilePlacement:
	var result := TilePlacement.new()
	result.layer = layer
	result.cell = absolute_cell
	result.item_name = item_name
	result.quarter_turns = posmod(quarter_turns + additional_turns, 4)

	return result
