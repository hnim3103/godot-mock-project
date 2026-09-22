extends SceneTree

const NPC_SCRIPT = preload("res://scenes/enemy/aquaman.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)


func _run() -> void:
	var main := load("res://scenes/main.tscn").instantiate() as Node3D
	var container: Node3D = main.get_node("Enemies")
	# Inspect spawn placement before gravity or navigation moves the NPC.
	container.process_mode = Node.PROCESS_MODE_DISABLED
	# Spawning must work even when the container's transform differs from the map.
	container.position = Vector3(7, 1, -3)
	container.rotation.y = 0.6
	root.add_child(main)

	for unused in range(8):
		await physics_frame

	var spawner := main.get_node("EnemySpawner")
	var map: Node3D = main.map_root
	var points: Array[Marker3D] = []

	for child in map.get_node("SpawnMarkers").get_children():
		if child.get_meta("kind", &"") == &"enemy" and child.get_meta("home_area_id", &"") != &"":
			points.append(child as Marker3D)

	_check(not points.is_empty(), "Fixture contains plateau enemy markers")
	_check(container.get_child_count() == points.size(), "Only assigned plateau markers spawn NPCs")
	if points.is_empty() or container.get_child_count() != points.size():
		main.free()
		quit(1)

		return

	for index in range(points.size()):
		var point := points[index]
		var npc := container.get_child(index) as NPC_SCRIPT
		_check(npc != null, "Spawned scene uses WanderingNPC")
		if npc == null:
			continue

		_check(
			npc.navigation_region == spawner.navigation_region,
			"NPC receives gameplay navigation region"
		)
		_check(
			(
				npc.navigation_agent.get_navigation_map()
				== spawner.navigation_region.get_navigation_map()
			),
			"Agent is bound to the region's navigation map when ready"
		)
		_check(
			npc.global_position.distance_to(point.global_position + spawner.spawn_offset) < 0.001,
			"Spawn world position is correct under a transformed container"
		)

		var collider: CollisionShape3D = npc.get_node("CollisionShape3D")
		var capsule := collider.shape as CapsuleShape3D
		_check(capsule != null, "NPC has a capsule collider")
		if capsule != null:
			var bottom := collider.global_position.y - capsule.height * 0.5
			_check(bottom >= point.global_position.y, "Collider starts above the plateau floor")

		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collider.shape
		query.transform = collider.global_transform
		query.exclude = [npc.get_rid()]
		_check(
			npc.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),
			"NPC does not overlap map collision at spawn"
		)

	spawner.spawn_plateau_enemies()
	_check(container.get_child_count() == points.size(), "Repeated spawn does not duplicate NPCs")
	points[0].name = "RenamedEnemySpawn"
	spawner.spawn_plateau_enemies()
	_check(
		container.get_child_count() == points.size(), "Renaming a marker does not duplicate its NPC"
	)

	var previous_id := container.get_child(0).get_instance_id()
	container.get_child(0).free()
	spawner.spawn_plateau_enemies()
	_check(container.get_child_count() == points.size(), "Explicit spawn can replace a freed NPC")
	_check(
		container.get_child(-1).get_instance_id() != previous_id, "Respawn creates a new instance"
	)

	main.free()
	print("Enemy spawner: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)
