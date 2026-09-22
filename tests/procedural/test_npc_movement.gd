extends SceneTree

var checks := 0
var failures := 0
var results: Array[bool] = []


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


func _wait_for_arrival(npc: CharacterBody3D, destination: Vector3, label: String) -> void:
	for unused in range(2400):
		await physics_frame
		if not results.is_empty():
			break

	_check(results == [true], label + " reports successful arrival")
	_check(
		npc.global_position.distance_to(destination) <= npc.arrival_distance + 0.05,
		label + " reaches destination, at %s" % npc.global_position
	)
	_check(
		Vector2(npc.velocity.x, npc.velocity.z).is_zero_approx(),
		label + " stops horizontal motion"
	)


func _run() -> void:
	var main := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(main)
	await _frames(30)

	var container := main.get_node("Enemies")
	_check(container.get_child_count() == 1, "Main spawns one plateau NPC")
	if container.get_child_count() != 1:
		main.free()
		quit(1)
		return

	var npc := container.get_child(0) as CharacterBody3D
	var player: CharacterBody3D = main.get_node("Player")
	npc.movement_finished.connect(func(reached: bool): results.append(reached))

	var resting_position := npc.global_position
	await _frames(60)
	_check(
		npc.global_position.distance_to(resting_position) < 0.01,
		"NPC waits for a command after spawn"
	)
	_check(npc.is_on_floor(), "Gravity settles the idle NPC")
	_check(not main.has_node("NPCMoveTarget"), "Fixed test target has been removed")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	_check(InputMap.event_is_action(key, "npc_move_here"), "E is bound to the NPC movement command")

	# Leave the plateau using the actual baked stairs, with Player still at the destination.
	player.global_position = Vector3(55, 2.1, 27)
	player.velocity = Vector3.ZERO
	await _frames(30)
	_check(player.is_on_floor(), "Player can choose a ground destination")

	var destination := player.global_position
	main._unhandled_input(key)
	await _wait_for_arrival(npc, destination, "Descent from spawn plateau")
	_check(npc.is_on_floor(), "NPC remains grounded after descending stairs")

	resting_position = npc.global_position
	await _frames(60)
	_check(npc.global_position.distance_to(resting_position) < 0.01, "NPC stays still after arrival")
	_check(results.size() == 1, "Arrival is emitted once")

	# Walking away does not turn the command into continuous chasing.
	player.global_position = Vector3(55, 4.1, 39)
	player.velocity = Vector3.ZERO
	await _frames(30)
	_check(
		npc.global_position.distance_to(resting_position) < 0.01,
		"NPC does not follow Player without another command"
	)
	_check(player.is_on_floor(), "Player can choose a destination on the original plateau")
	results.clear()
	destination = player.global_position
	main._unhandled_input(key)
	await _wait_for_arrival(npc, destination, "Ascent to the original plateau")

	results.clear()
	_check(npc.move_to(Vector3(55, 2, 27)), "Accept a replacement destination")
	await _frames(10)
	_check(npc.move_to(Vector3(58, 4, 40)), "Retarget while moving")
	await _wait_for_arrival(npc, Vector3(58, 4, 40), "Replacement command")
	_check(not npc.move_to(Vector3(INF, 4, 38)), "Reject non-finite destinations")

	npc.move_to(Vector3(55, 2, 27))
	npc.stop_moving()
	resting_position = npc.global_position
	await _frames(30)
	_check(npc.global_position.distance_to(resting_position) < 0.01, "Stop cancels a queued command")

	results.clear()
	npc.navigation_agent.navigation_layers = 2
	npc.move_to(Vector3(55, 2, 27))
	await _frames(30)
	_check(results == [false], "An empty path reports failure")
	_check(npc.global_position.distance_to(resting_position) < 0.01, "An empty path does not move the NPC")
	_check(npc.is_on_floor(), "Gravity remains active after navigation failure")

	main.free()
	print("NPC movement: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
