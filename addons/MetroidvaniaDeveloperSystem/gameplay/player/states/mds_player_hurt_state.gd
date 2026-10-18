@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_hurt_state.svg")
class_name MDSPlayerHurtState
extends MDSPlayerState
## Hit: pushed back ([MDSKnockback]) and without control until the hit-stun ends.

## Seconds without control when the knockback gives none.
@export var min_time := 0.12

func enter(_previous: StringName, _data: Dictionary) -> void:
	if player.attacks and player.attacks.has_method(&"cancel"):
		player.attacks.call(&"cancel")

func physics_update(delta: float) -> void:
	fall(delta)
	player.move()
	var stunned: bool = player.knockback != null and player.knockback.call(&"is_stunned")
	if machine.time_in_state < min_time or stunned:
		return
	if not land_or_fall():
		go(&"Fall")
