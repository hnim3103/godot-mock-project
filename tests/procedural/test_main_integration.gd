extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)


func _run() -> void:
	var main := load("res://scenes/main.tscn").instantiate() as Node3D
	var spawn_state := {"ready": false, "camera_snapped": false}
	main.map_ready.connect(
		func(_map: Node3D):
			spawn_state.ready = true

			var spawn_camera: Camera3D = main.get_node("Camera3D")
			var framed: Transform3D = main.get_node("PhantomCamera3D").call("get_transform_output")
			spawn_state.camera_snapped = (
				spawn_camera.global_position.distance_to(framed.origin) < 0.1
			)
	)
	root.add_child(main)

	var map: Node3D = main.map_root
	var player: CharacterBody3D = main.get_node("Player")
	var phantom: Node3D = main.get_node("PhantomCamera3D")

	for unused in range(8):
		await physics_frame

	var spawn: Marker3D = map.get_node("SpawnMarkers/PlayerSpawn")
	_check(map.get_script() == null, "Saved map has no runtime script")
	_check(
		map.scene_file_path == "res://scenes/maps/forest_12345.tscn", "Main instances the saved map"
	)
	_check(not map.get_node("GroundGrid").get_used_cells().is_empty(), "Saved ground tiles load")
	_check(
		map.find_children("*", "NavigationRegion3D", true, false).is_empty(),
		"Saved map does not contain navigation"
	)

	var region := map.get_parent() as NavigationRegion3D
	_check(
		region != null and region.navigation_mesh != null, "Main uses an authored navigation region"
	)
	_check(
		not main.has_node("ProceduralMap") and not map.has_node("MapGenerator"),
		"Main does not generate at startup"
	)
	_check(
		player.global_position.distance_to(spawn.global_position + main.player_spawn_offset) < 0.15,
		"Player starts at saved marker"
	)
	_check(player.process_mode != Node.PROCESS_MODE_DISABLED, "Player processing resumes")
	_check(phantom.get("follow_target") == player, "Camera follows existing Player")
	# Observe the spawn event before the camera host's later interpolation updates.
	_check(
		spawn_state.ready and spawn_state.camera_snapped, "Camera is framed when map_ready fires"
	)
	_check(
		root.find_children("Player", "CharacterBody3D", true, false).size() == 1,
		"Only one gameplay Player"
	)
	_check(
		map.get_node("SpawnMarkers").find_children("*", "MeshInstance3D", true, false).is_empty(),
		"No debug marker meshes in gameplay"
	)

	var world := spawn.global_position
	var query := PhysicsRayQueryParameters3D.create(world + Vector3.UP * 5, world - Vector3.UP, 1)
	query.exclude = [player.get_rid()]

	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	_check(
		not hit.is_empty() and absf(hit.position.y - world.y) < 0.05,
		"Saved floor collision under Player"
	)

	var previous_map := map.get_instance_id()
	var previous_player := player.get_instance_id()
	player.global_position += Vector3(5, 0, 5)
	player.velocity = Vector3(2, 3, 1)
	_check(main.respawn_player(), "Respawn uses saved marker")
	_check(player.velocity == Vector3.ZERO, "Respawn clears velocity")
	await physics_frame
	await physics_frame
	_check(
		player.get_instance_id() == previous_player and map.get_instance_id() == previous_map,
		"Respawn keeps Player and saved map"
	)
	_check(
		player.global_position.distance_to(spawn.global_position + main.player_spawn_offset) < 0.15,
		"Respawn returns to marker"
	)
	main.free()
	print("Main integration: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
