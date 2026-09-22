extends CharacterBody3D
## A small keyboard-controlled probe for checking generated floor/ramp collision.

var active := false
var speed := 5.0
var home := Vector3.ZERO
var sprite: AnimatedSprite3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(55)
	floor_snap_length = 0.4

	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.3

	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.65
	add_child(collider)

	var source := load("res://scenes/player/player.tscn") as PackedScene
	var original := source.instantiate()
	sprite = original.get_node("Visual").duplicate() as AnimatedSprite3D
	original.free()
	sprite.pixel_size = 0.027
	sprite.position.y = 0.86
	sprite.play("walk_front")
	add_child(sprite)


func reset_at(point: Vector3) -> void:
	home = point + Vector3.UP * 0.12
	global_position = home
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not active:
		return

	var input := Vector2.ZERO
	if get_viewport().gui_get_focus_owner() == null:
		input.x = (
			float(Input.is_physical_key_pressed(KEY_D))
			- float(Input.is_physical_key_pressed(KEY_A))
		)
		input.y = (
			float(Input.is_physical_key_pressed(KEY_S))
			- float(Input.is_physical_key_pressed(KEY_W))
		)

	var direction := Vector3.ZERO
	if input.length_squared() > 0:
		direction = (Vector3(1, 0, -1) * input.x + Vector3(1, 0, 1) * input.y).normalized()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.5

	move_and_slide()
	if direction.length_squared() > 0:
		var animation := (
			"walk_side"
			if absf(direction.x) > absf(direction.z)
			else "walk_front" if direction.z > 0 else "walk_back"
		)
		sprite.flip_h = direction.x < 0
		sprite.play(animation)
	else:
		sprite.pause()

	if global_position.y < -10:
		reset_at(home - Vector3.UP * 0.12)
