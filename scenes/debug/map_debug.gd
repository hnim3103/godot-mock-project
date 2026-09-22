extends Node3D

@onready var generator: MapGenerator = $ProceduralMap/MapGenerator
var camera: Camera3D
var player: CharacterBody3D
var seed_input: LineEdit
var size_input: OptionButton
var elevation_input: CheckBox
var route_input: CheckBox
var play_button: Button
var status: Label
var seed_label: Label
var route_mesh: MeshInstance3D
var controls: Array[Button] = []
var target := Vector3.ZERO
var yaw := PI / 4.0
var zoom := 100.0
var playing := false
var dragging := false
var capture_path := ""
var save_dialog: FileDialog


func _ready() -> void:
	generator.config = generator.config.duplicate()
	_create_world()
	_create_ui()
	generator.generation_completed.connect(_on_generated)
	generator.generation_failed.connect(_on_failed)
	generator.map_cleared.connect(_on_cleared)
	generator.regenerate()

	var args := OS.get_cmdline_user_args()
	var capture_index := args.find("--capture")
	if capture_index >= 0 and capture_index + 1 < args.size():
		capture_path = args[capture_index + 1]
		_capture.call_deferred()


func _create_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("152b2c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d4e7d4")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 1000
	add_child(camera)
	camera.make_current()
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/procedural/procedural_player.gd"))
	add_child(player)
	player.hide()
	route_mesh = MeshInstance3D.new()
	add_child(route_mesh)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.08, 0.085, 0.96)
	style.border_color = Color("315551")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12

	return style


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.offset_left = 12
	margin.offset_right = -12
	margin.offset_top = 12
	canvas.add_child(margin)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	margin.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "FOREST / MAP LAB"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("8df0c8"))
	column.add_child(title)

	var row := HBoxContainer.new()
	column.add_child(row)

	seed_input = LineEdit.new()
	seed_input.placeholder_text = "Seed"
	seed_input.text = str(generator.config.seed_value)
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_input.custom_minimum_size.x = 110
	seed_input.text_submitted.connect(func(_text: String): _generate(false))
	row.add_child(seed_input)

	size_input = OptionButton.new()

	for size in [24, 32, 48, 64]:
		size_input.add_item("%d × %d" % [size, size], size)

	size_input.select(1)
	row.add_child(size_input)

	elevation_input = CheckBox.new()
	elevation_input.text = "Elevation"
	elevation_input.button_pressed = generator.config.enable_elevation
	elevation_input.focus_mode = Control.FOCUS_NONE
	row.add_child(elevation_input)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_button(buttons, "Generate", func(): _generate(false))
	_button(buttons, "Random", func(): _generate(true))
	_button(buttons, "Replay Seed", func(): _regenerate())
	_button(buttons, "Clear", func(): generator.clear_map())
	_button(buttons, "Save Scene", _show_save_dialog)

	save_dialog = FileDialog.new()
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_RESOURCES
	save_dialog.filters = PackedStringArray(["*.tscn ; Godot scene"])
	save_dialog.file_selected.connect(_save_scene)
	add_child(save_dialog)

	var tools_row := HBoxContainer.new()
	column.add_child(tools_row)
	play_button = _button(tools_row, "Playtest", func(): _toggle_play())

	route_input = CheckBox.new()
	route_input.text = "Main Route"
	route_input.focus_mode = Control.FOCUS_NONE
	route_input.toggled.connect(func(value: bool): route_mesh.visible = value)
	tools_row.add_child(route_input)
	_button(
		tools_row,
		"Library",
		func(): get_tree().change_scene_to_file("res://scenes/debug/tile_preview.tscn")
	)

	seed_label = Label.new()
	seed_label.add_theme_color_override("font_color", Color("b1c7bd"))
	column.add_child(seed_label)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 13)
	column.add_child(status)

	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.offset_top = -72
	bottom.offset_bottom = -12
	bottom.add_theme_stylebox_override("panel", _panel_style())
	canvas.add_child(bottom)

	var hint := Label.new()
	hint.text = "Right-drag: orbit · Scroll: zoom\nPlaytest: WASD · Esc: overview · Save the scene to use the map in game"
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(hint)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	controls.append(button)

	return button


func _generate(random_seed: bool) -> void:
	if generator.is_generating:
		return

	if not random_seed and not seed_input.text.is_valid_int():
		status.text = "Seed must be an integer."
		return

	seed_input.release_focus()
	status.text = "Generating map…"

	for button in controls:
		button.disabled = true

	await get_tree().process_frame

	var previous := generator.config
	var config := previous.duplicate() as MapConfig
	config.map_size = Vector2i.ONE * size_input.get_selected_id()
	config.enable_elevation = elevation_input.button_pressed
	generator.config = config

	var ok := (
		generator.generate_random() if random_seed else generator.generate(seed_input.text.to_int())
	)
	if not ok:
		generator.config = previous

	for button in controls:
		button.disabled = false


func _regenerate() -> void:
	seed_input.release_focus()
	generator.regenerate()


func _on_generated(seed_value: int) -> void:
	seed_input.text = str(seed_value)

	var data := generator.current_data
	seed_label.text = (
		"SEED %d   ·   %d × %d   ·   %.0f ms"
		% [seed_value, data.size.x, data.size.y, generator.generation_ms]
	)
	status.add_theme_color_override("font_color", Color("b1c7bd"))
	status.text = (
		"%d plateaus · %d stairways · %d spawn points | Green: start · Yellow: exit"
		% [data.plateaus.size(), data.stairs.size(), data.spawns.size()]
	)
	playing = false
	player.active = false
	player.hide()
	player.reset_at(generator.cell_world(data.start_cell))
	play_button.text = "Playtest"
	target = generator.to_global(Vector3(data.size.x, 0, data.size.y))
	zoom = _overview_zoom()
	_draw_route()
	_update_camera()


func _on_failed(_seed_value: int, errors: PackedStringArray) -> void:
	status.add_theme_color_override("font_color", Color("ffa4a4"))
	status.text = "\n".join(errors)


func _on_cleared() -> void:
	playing = false
	player.active = false
	player.hide()
	route_mesh.mesh = null
	seed_label.text = "No map generated"
	status.text = "Choose a seed, then click Generate to create a new map."
	play_button.text = "Playtest"


func _toggle_play() -> void:
	if not generator.has_generated:
		return

	playing = not playing
	player.active = playing
	player.visible = playing
	play_button.text = "Overview" if playing else "Playtest"
	if playing:
		yaw = PI / 4.0
		zoom = 24.0
	else:
		target = generator.to_global(
			Vector3(generator.current_data.size.x, 0, generator.current_data.size.y)
		)
		zoom = _overview_zoom()


func _overview_zoom() -> float:
	var viewport := get_viewport().get_visible_rect().size
	var extent := float(maxi(generator.current_data.size.x, generator.current_data.size.y))

	return maxf(
		extent * 2.15 * viewport.y / maxf(200, viewport.y - 310), extent * 3.1 / viewport.aspect()
	)


func _draw_route() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("91ffe2")
	material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var points := generator.current_data.main_path

	for i in range(1, points.size()):
		mesh.surface_add_vertex(generator.cell_world(points[i - 1]) + Vector3.UP * 0.12)
		mesh.surface_add_vertex(generator.cell_world(points[i]) + Vector3.UP * 0.12)

	mesh.surface_end()
	route_mesh.mesh = mesh
	route_mesh.visible = route_input.button_pressed


func _process(delta: float) -> void:
	if playing:
		target = target.lerp(player.global_position, 1.0 - exp(-delta * 6.0))

	_update_camera()


func _update_camera() -> void:
	camera.size = zoom
	camera.position = target + Vector3(sin(yaw) * 80, 85, cos(yaw) * 80)
	camera.look_at(target)
	# Frame the world below the toolbar.
	camera.v_offset = zoom * 0.105


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and playing:
		_toggle_play()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed

		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(10.0, zoom * 0.9)

		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(400.0, zoom * 1.1)

	if event is InputEventMouseMotion and dragging and not playing:
		yaw -= event.relative.x * 0.006


func _capture() -> void:
	for unused in range(8):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_path)
	get_tree().quit()


func _show_save_dialog() -> void:
	if not generator.has_generated or generator.is_generating:
		status.text = "Generate a map before saving the scene."
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/maps"))
	save_dialog.current_dir = "res://scenes/maps"
	save_dialog.current_file = "forest_%d.tscn" % generator.last_seed
	save_dialog.popup_centered_ratio(0.75)


func _save_scene(path: String) -> void:
	# FileDialog confirms replacement before emitting file_selected.
	var error := preload("res://scripts/procedural/map_scene_exporter.gd").save_map(
		generator, path, true
	)
	status.text = (
		"Map saved: " + path if error == OK else "Could not save scene: " + error_string(error)
	)
