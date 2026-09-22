extends SceneTree
## godot --headless --path . --script scripts/tools/export_forest_map.gd -- --seed 12345 --output res://scenes/maps/forest_12345.tscn


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := 12345
	var output := ""

	for option in ["--seed", "--output"]:
		var index := args.find(option)
		if index < 0:
			continue

		if index + 1 >= args.size() or (option == "--seed" and not args[index + 1].is_valid_int()):
			printerr("Invalid argument: ", option)
			quit(1)

			return

		if option == "--seed":
			seed_value = args[index + 1].to_int()
		else:
			output = args[index + 1]

	if output.is_empty():
		output = "res://scenes/maps/forest_%d.tscn" % seed_value

	var scene := load("res://scenes/procedural_map.tscn").instantiate() as Node3D
	root.add_child(scene)

	var generator := scene.get_node("MapGenerator") as MapGenerator
	var error := ERR_CANT_CREATE
	if generator.generate(seed_value):
		error = preload("res://scripts/procedural/map_scene_exporter.gd").save_map(
			generator, output, "--overwrite" in args
		)
	else:
		printerr(generator.last_errors)

	print("Export map: %s — %s" % [output, error_string(error)])
	scene.free()
	quit(0 if error == OK else 1)
