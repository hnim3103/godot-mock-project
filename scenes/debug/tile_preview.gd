extends Node3D
## Contact sheet for original items and representative generated masks.


func _ready() -> void:
	var catalog := load("res://resources/procedural/forest_tile_catalog.tres") as TileCatalog
	var names: Array[String] = []

	for id in range(32):
		names.append(catalog.mesh_library.get_item_name(id))

	for mask in range(16):
		names.append("path_%02d_15" % mask)

	for mask in range(1, 16):
		names.append("cliff_%02d" % mask)

	for i in range(names.size()):
		var mesh := MeshInstance3D.new()
		mesh.mesh = catalog.mesh_library.get_item_mesh(catalog.get_item_id(StringName(names[i])))
		mesh.position = Vector3((i % 8) * 4.2, 0, (i / 8) * 5.0)
		add_child(mesh)

		var label := Label3D.new()
		label.text = names[i]
		label.font_size = 22
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = mesh.position + Vector3(0, 2, 0)
		add_child(label)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("152b2c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.8
	environment.environment = env
	add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	add_child(light)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 58.0
	camera.position = Vector3(32, 50, 54)
	add_child(camera)
	camera.look_at(Vector3(15, 0, 18))

	var canvas := CanvasLayer.new()
	add_child(canvas)

	var back := Button.new()
	back.text = "← Map Lab   |   Library: 32 source tiles + procedural paths/walls"
	back.position = Vector2(12, 12)
	back.pressed.connect(
		func(): get_tree().change_scene_to_file("res://scenes/debug/map_debug.tscn")
	)
	canvas.add_child(back)

	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--capture":
		for unused in range(8):
			await get_tree().process_frame

		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[1])
		get_tree().quit()
