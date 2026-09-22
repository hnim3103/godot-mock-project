extends CharacterBody3D

@export_group("Movement")
@export var move_speed: float = 5.0
@export var jump_impulse: float = 14.0
@export_range(0.1, 100.0) var acceleration: float = 30.0
@export_range(0.1, 100.0) var deceleration: float = 35.0
@export_range(0.1, 100.0) var air_acceleration: float = 12.0
@export_range(0.1, 10.0) var gravity_scale: float = 3.0
@export_range(1.0, 100.0) var terminal_fall_speed: float = 50.0
## Disable controls for dialogue/stuns while keeping gravity and collision active.
@export var controls_enabled: bool = true

@export_group("Visual")
## Turn off when another system owns animation (e.g. combat).
@export var movement_animation_enabled: bool = true

@onready var visual: AnimatedSprite3D = $Visual

var _facing: String = "front"
var _flip_side: bool = false


func _ready() -> void:
	if movement_animation_enabled:
		visual.play(&"idle_front")


func _physics_process(delta: float) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var can_read_input := controls_enabled and not (focus is LineEdit or focus is TextEdit)
	var input_vector := Vector2.ZERO
	if can_read_input:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var direction := get_movement_direction(input_vector)
	var target_velocity := direction * maxf(move_speed, 0.0)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if not input_vector.is_zero_approx() else deceleration
	if not is_on_floor():
		rate = air_acceleration

	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		velocity.y = 0.0
		if can_read_input and Input.is_action_just_pressed("jump"):
			velocity.y = maxf(jump_impulse, 0.0)
	else:
		velocity.y = maxf(
			velocity.y + get_gravity().y * gravity_scale * delta, -terminal_fall_speed
		)

	move_and_slide()
	if movement_animation_enabled:
		_update_movement_animation()


## Camera-relative X/Z motion; preserve analog strength and cap diagonal input at 1.
func get_movement_direction(input_vector: Vector2) -> Vector3:
	var forward := _camera_forward()
	var right := forward.cross(Vector3.UP).normalized()
	var input := input_vector.limit_length(1.0)

	return right * input.x - forward * input.y


func _camera_forward() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.FORWARD

	var forward := -camera.global_basis.z
	forward.y = 0.0
	# A camera looking straight down has no horizontal forward projection.
	if forward.length_squared() < 0.0001:
		forward = camera.global_basis.y
		forward.y = 0.0

	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD


func _update_movement_animation() -> void:
	# Use actual displacement so pushing against a wall does not keep the walk cycle playing.
	var motion := get_real_velocity()
	motion.y = 0.0

	var moving := motion.length_squared() > 0.01
	if moving:
		var forward := _camera_forward()
		var right := forward.cross(Vector3.UP).normalized()
		var screen_motion := Vector2(motion.dot(right), -motion.dot(forward))
		if absf(screen_motion.x) > absf(screen_motion.y):
			_facing = "side"
			_flip_side = screen_motion.x < 0.0
		else:
			_facing = "front" if screen_motion.y > 0.0 else "back"

	visual.flip_h = _facing == "side" and _flip_side

	var state := "jump" if not is_on_floor() else "walk" if moving else "idle"
	var animation := StringName(state + "_" + _facing)
	if visual.sprite_frames.has_animation(animation) and visual.animation != animation:
		# Do not restart a completed non-looping jump every frame while airborne.
		visual.play(animation)
