extends Node3D
## Gameplay consumes a saved map. Generation belongs to Map Lab/export tools.

signal map_ready(map: Node3D)

@export var player_spawn_offset: Vector3 = Vector3(0.0, 0.1, 0.0)
@export var map_root: Node3D
@onready var player: CharacterBody3D = $Player
@onready var phantom_camera: Node3D = $PhantomCamera3D
@onready var camera: Camera3D = $Camera3D

var _spawn_pending := false
var _player_process_mode: ProcessMode


func _ready() -> void:
	_player_process_mode = player.process_mode
	set_physics_process(false)
	respawn_player()


func respawn_player() -> bool:
	_spawn_pending = false
	set_physics_process(false)
	if not is_instance_valid(map_root):
		push_error("Main requires map_root to reference the saved map scene.")
		player.process_mode = Node.PROCESS_MODE_DISABLED

		return false

	var spawn := map_root.get_node_or_null("SpawnMarkers/PlayerSpawn") as Marker3D
	if spawn == null:
		push_error("Map requires a Marker3D at SpawnMarkers/PlayerSpawn.")
		player.process_mode = Node.PROCESS_MODE_DISABLED

		return false

	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.velocity = Vector3.ZERO
	player.global_position = spawn.global_position + player_spawn_offset
	player.reset_physics_interpolation()
	_spawn_pending = true
	set_physics_process(true)

	return true


func _physics_process(_delta: float) -> void:
	if not _spawn_pending:
		return

	_spawn_pending = false
	if phantom_camera.has_method("teleport_position"):
		phantom_camera.call("teleport_position")
		camera.global_transform = phantom_camera.call("get_transform_output")
		camera.reset_physics_interpolation()

	player.process_mode = _player_process_mode
	set_physics_process(false)
	map_ready.emit(map_root)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("npc_move_here"):
		return

	if not player.is_on_floor():
		return

	for child in $Enemies.get_children():
		if child is WanderingNPC:
			child.move_to(player.global_position)
			break

	get_viewport().set_input_as_handled()
