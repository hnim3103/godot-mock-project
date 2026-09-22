extends Node
## Spawn one NPC per plateau marker; unassigned ground markers are skipped.

const NPC_SCRIPT = preload("res://scenes/enemy/aquaman.gd")

@export var map_root: Node3D
@export var navigation_region: NavigationRegion3D
@export var enemy_container: Node3D
@export var enemy_scene: PackedScene
@export var spawn_offset: Vector3 = Vector3(0.0, 0.05, 0.0)

var _spawned: Dictionary = {}


func _ready() -> void:
	spawn_plateau_enemies.call_deferred()


func spawn_plateau_enemies() -> void:
	if not _has_dependencies():
		return

	var markers := map_root.get_node_or_null("SpawnMarkers")
	var areas := map_root.get_node_or_null("MapAreas")
	if markers == null or areas == null:
		push_error("EnemySpawner requires SpawnMarkers and MapAreas in the saved map.")
		return

	for child in markers.get_children():
		var point := child as Marker3D
		if point != null and point.get_meta("kind", &"") == &"enemy":
			_spawn_at_point(point, areas)


func _has_dependencies() -> bool:
	if (
		not is_instance_valid(map_root)
		or not is_instance_valid(navigation_region)
		or not is_instance_valid(enemy_container)
		or enemy_scene == null
	):
		push_error("Assign Map Root, Navigation Region, Enemy Container and Enemy Scene.")
		return false

	return true


func _spawn_at_point(point: Marker3D, areas: Node) -> void:
	var area_id := StringName(point.get_meta("home_area_id", &""))
	if area_id == &"" or is_instance_valid(_spawned.get(point)):
		return

	var area := areas.get_node_or_null(NodePath(String(area_id))) as Marker3D
	if area == null:
		push_warning("Spawn point %s refers to missing home area %s." % [point.name, area_id])
		return

	var instance := enemy_scene.instantiate()
	if not instance is NPC_SCRIPT:
		push_error("Enemy Scene must use WanderingNPC or a script that extends it.")
		instance.free()

		return

	var npc := instance as NPC_SCRIPT
	npc.setup(navigation_region)
	# Position and context must be available when the NPC's _ready() runs.
	npc.position = enemy_container.to_local(point.global_position + spawn_offset)
	enemy_container.add_child(npc)
	_spawned[point] = npc
