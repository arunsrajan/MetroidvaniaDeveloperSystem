@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_dead_state.svg")
class_name MDSPlayerDeadState
extends MDSPlayerState
## Health ran out: down, no control, while [MDSGameplay] takes the player back to its bench.

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.velocity.x = 0.0
	if player.attacks and player.attacks.has_method(&"cancel"):
		player.attacks.call(&"cancel")

func physics_update(delta: float) -> void:
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.config.ground_decel * delta)
	fall(delta)
	player.move()
