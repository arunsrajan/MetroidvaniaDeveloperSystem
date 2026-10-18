@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_slide_state.svg")
class_name MDSPlayerSlideState
extends MDSPlayerState
## With [code]slide[/code]: down + dash on the ground slides along it, the body half as tall, under
## low gaps ([member MDSMovementConfig.slide_speed] for [member MDSMovementConfig.slide_time] s).
## Under a low ceiling it ends crouching, until there is room to stand.

func _init() -> void:
	required_ability = "slide"
	trigger = Trigger.GROUND
	priority = 40

var _dir := 1

func can_enter() -> bool:
	return super() and player.is_on_floor() and player.input_y() > 0.5 and player.pressed("dash")

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.buffer.consume("dash")
	_dir = player.facing
	player.set_body_height(0.5)

func physics_update(delta: float) -> void:
	player.velocity.x = player.config.slide_speed * _dir
	fall(delta)
	player.move()
	if not player.is_on_floor():
		go(&"Fall")
		return
	if machine.time_in_state < player.config.slide_time and not player.is_on_wall():
		return
	if player.can_stand():
		go(&"Run" if absf(player.input_x()) > 0.01 else &"Idle")
	else:
		machine.force(&"Crouch")
