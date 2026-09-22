class_name WanderingNPC
extends CharacterBody3D
## Follow destinations requested by the player on the existing navigation map.

signal movement_finished(reached_target: bool)

@export_group("Movement")
@export_range(0.1, 10.0) var move_speed: float = 2.0
## Leave room for the Player collider when the player stays at the destination.
@export_range(0.05, 3.0) var arrival_distance: float = 1.5

var navigation_region: NavigationRegion3D

var _destination := Vector3.ZERO
var _target_pending := false
var _moving := false

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D


## Called before add_child(), so @onready references are not available here.
func setup(region: NavigationRegion3D) -> void:
	navigation_region = region


func _ready() -> void:
	if not is_instance_valid(navigation_region):
		push_error("WanderingNPC requires a navigation region before spawning.")
		set_physics_process(false)
		return

	navigation_agent.set_navigation_map(navigation_region.get_navigation_map())
	navigation_agent.target_desired_distance = arrival_distance


## Queue the destination until the navigation map has synchronized.
func move_to(destination: Vector3) -> bool:
	if not destination.is_finite():
		return false

	_destination = destination
	_target_pending = true
	_moving = false

	velocity.x = 0.0
	velocity.z = 0.0

	return true


func stop_moving() -> void:
	_target_pending = false
	_moving = false
	velocity.x = 0.0
	velocity.z = 0.0


func _physics_process(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

	if _target_pending and _navigation_is_ready():
		navigation_agent.target_position = _destination
		_target_pending = false
		_moving = true

	if _moving:
		_update_movement(delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity += get_gravity() * delta

	move_and_slide()


func _navigation_is_ready() -> bool:
	var navigation_map := navigation_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return false

	# The world's empty map can synchronize before the region's polygons are published.
	var owner := NavigationServer3D.map_get_closest_point_owner(navigation_map, global_position)
	return owner == navigation_region.get_rid()


func _update_movement(delta: float) -> void:
	# Update the agent once per physics frame, only while following a destination.
	var next_position := navigation_agent.get_next_path_position()
	var path := navigation_agent.get_current_navigation_path()
	if path.is_empty():
		_finish_movement(false)
		return

	if navigation_agent.is_navigation_finished():
		_finish_movement(global_position.distance_to(_destination) <= arrival_distance + 0.05)
		return

	var direction := next_position - global_position
	direction.y = 0.0

	# Cap each step to avoid overshooting short path segments.
	var speed := minf(move_speed, direction.length() / delta)
	var horizontal_velocity := direction.normalized() * speed
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z


func _finish_movement(reached_target: bool) -> void:
	stop_moving()
	movement_finished.emit(reached_target)
