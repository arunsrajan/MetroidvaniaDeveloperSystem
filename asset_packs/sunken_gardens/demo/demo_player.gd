extends CharacterBody2D
## A minimal player for the Sunken Gardens demo: Left/Right (or A/D) run, Space/Up (or W)
## jumps. Ledges are one-way: jump up through them, land on top.

@export var speed := 320.0
@export var jump_velocity := 700.0
@export var gravity := 900.0

func _physics_process(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity * delta, 1400.0)
	var dir := Input.get_axis(&"ui_left", &"ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir += 1.0
	velocity.x = clampf(dir, -1.0, 1.0) * speed
	var jump := Input.is_action_just_pressed(&"ui_accept") or Input.is_action_just_pressed(&"ui_up") or Input.is_key_pressed(KEY_W)
	if jump and is_on_floor():
		velocity.y = -jump_velocity
	move_and_slide()
