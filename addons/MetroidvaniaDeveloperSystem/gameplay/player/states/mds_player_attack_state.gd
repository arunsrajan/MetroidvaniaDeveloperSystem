@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_attack_state.svg")
class_name MDSPlayerAttackState
extends MDSPlayerState
## A rooted attack (the charged attack): the player stands its ground until the attack is over.

func physics_update(delta: float) -> void:
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.config.ground_decel * delta)
	fall(delta)
	player.move()
	var busy: bool = player.attacks != null and player.attacks.call(&"is_attacking")
	if busy and machine.time_in_state < 2.0:
		return
	if not land_or_fall():
		go(&"Fall")
