extends SceneTree

var failures := 0
var checks := 0
var player: CharacterBody3D
var map_root: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)


func _frames(count: int) -> void:
	for unused in range(count):
		await physics_frame


func _release() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back", "jump"]:
		Input.action_release(action)


func _warp(point: Vector3) -> void:
	_release()
	player.global_position = point + Vector3.UP * 0.12
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _frames(20)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	player = main.get_node("Player") as CharacterBody3D
	map_root = main.map_root
	await _frames(30)
	_check(
		not map_root.get_node("GroundGrid").get_used_cells().is_empty(), "Main has a saved world"
	)

	var home: Vector3 = map_root.get_node("SpawnMarkers/PlayerSpawn").global_position
	_check(player.is_on_floor(), "Gravity settles the existing Player on the floor")
	_check(player.get_node("Visual").animation == &"idle_front", "Initial idle animation")

	for mapping in [
		[KEY_W, "move_forward"],
		[KEY_UP, "move_forward"],
		[KEY_A, "move_left"],
		[KEY_LEFT, "move_left"],
		[KEY_S, "move_back"],
		[KEY_DOWN, "move_back"],
		[KEY_D, "move_right"],
		[KEY_RIGHT, "move_right"],
		[KEY_SPACE, "jump"]
	]:
		var event := InputEventKey.new()
		event.physical_keycode = mapping[0]
		event.pressed = true
		_check(InputMap.event_is_action(event, mapping[1]), "Physical key mapping: %s" % mapping[1])

	var before := player.global_position
	Input.action_press("move_forward")
	await _frames(30)
	_check(player.global_position.z < before.z - 1.0, "W moves forward relative to the camera")
	_check(player.get_node("Visual").animation == &"walk_back", "Forward walk animation")
	_check(
		absf(Vector2(player.velocity.x, player.velocity.z).length() - player.move_speed) < 0.05,
		"Accelerates to move_speed"
	)
	_release()
	await _frames(20)
	_check(
		Vector2(player.velocity.x, player.velocity.z).length() < 0.01,
		"Release decelerates to a stop"
	)
	_check(player.get_node("Visual").animation == &"idle_back", "Idle retains the last facing")

	await _warp(home)
	Input.action_press("move_right")
	Input.action_press("move_forward")
	await _frames(30)
	_check(
		Vector2(player.velocity.x, player.velocity.z).length() <= player.move_speed + 0.01,
		"Diagonal motion is not faster"
	)
	_release()
	await _warp(home)
	Input.action_press("move_left")
	await _frames(20)
	_check(
		player.get_node("Visual").animation == &"walk_side" and player.get_node("Visual").flip_h,
		"Left motion mirrors the side animation"
	)
	player.controls_enabled = false
	await _frames(20)
	_check(
		Vector2(player.velocity.x, player.velocity.z).length() < 0.01,
		"Controls can be disabled for gameplay"
	)
	player.controls_enabled = true
	_release()

	await _warp(home)
	Input.action_press("jump")
	await _frames(3)
	_check(not player.is_on_floor() and player.velocity.y > 0, "Space jumps from the floor")
	_check(String(player.get_node("Visual").animation).begins_with("jump_"), "Airborne animation")
	Input.action_release("jump")
	await _frames(2)

	var upward_speed := player.velocity.y
	Input.action_press("jump")
	await _frames(2)
	_check(player.velocity.y < upward_speed, "No midair double jump")
	# Keep space held while landing: it must not auto-jump again.
	await _frames(120)
	_check(
		player.is_on_floor() and absf(player.global_position.y - home.y) < 0.1,
		"Gravity lands without repeated jumps while holding Space"
	)
	_release()

	var camera := main.get_node("Camera3D") as Camera3D
	var saved_basis := camera.global_basis
	camera.global_basis = Basis(Vector3.UP, PI / 2.0) * saved_basis

	var rotated: Vector3 = player.get_movement_direction(Vector2.UP)
	_check(rotated.x < -0.99 and absf(rotated.z) < 0.01, "Direction follows camera yaw")
	camera.global_basis = saved_basis

	# Walk into the generated outer boundary using the actual gameplay capsule.
	await _warp(Vector3(1.5, home.y, home.z))
	Input.action_press("move_left")
	await _frames(60)
	_check(
		player.global_position.x > 0.8 and player.is_on_wall(),
		"Boundary collision prevents leaving the map"
	)
	_release()

	# Cross every stair flight in both directions with the original large Player capsule.
	for flight in map_root.get_meta("stair_flights", []):
		var bottom := map_root.to_global(flight.entrances[0])
		var top := map_root.to_global(flight.exits[0])

		for endpoints in [[bottom, top], [top, bottom]]:
			await _warp(endpoints[0])

			var direction: Vector3 = (endpoints[1] - endpoints[0]) * Vector3(1, 0, 1)
			direction = direction.normalized()

			var action := (
				"move_right"
				if direction.x > 0.5
				else (
					"move_left"
					if direction.x < -0.5
					else "move_back" if direction.z > 0.5 else "move_forward"
				)
			)
			Input.action_press(action)

			var reached := false

			for unused in range(300):
				await physics_frame
				if player.global_position.distance_to(endpoints[1]) < 0.6:
					reached = true
					break

			_release()
			_check(
				reached,
				(
					"Gameplay Player traverses ramp %s -> %s (at %s)"
					% [endpoints[0], endpoints[1], player.global_position]
				)
			)

	_release()
	main.free()
	print("Player movement: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
