@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_crouch_state.svg")
class_name MDSPlayerCrouchState
extends MDSPlayerState
## Down held on the ground: the body is half as tall (low passages), and the player stops. Down +
## jump on a one-way platform drops through it. Getting up needs room overhead.

func _init() -> void:
	trigger = Trigger.GROUND
	priority = 5

func can_enter() -> bool:
	return player != null and player.is_on_floor() and player.input_y() > 0.5

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.set_body_height(0.5)

func physics_update(delta: float) -> void:
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.config.ground_decel * delta)
	fall(delta)
	player.move()
	if not player.is_on_floor():
		go(&"Fall")
		return
	if player.try_ground_moves():
		return
	if player.input_y() < 0.5 and player.can_stand():
		go(&"Idle")
