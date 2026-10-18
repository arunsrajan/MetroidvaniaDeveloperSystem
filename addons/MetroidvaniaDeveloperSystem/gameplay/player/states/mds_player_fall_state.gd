@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_fall_state.svg")
class_name MDSPlayerFallState
extends MDSPlayerState
## In the air, going down (or anywhere in the air no other state is).

func physics_update(delta: float) -> void:
	run(delta)
	fall(delta)
	player.move()
	if land_or_fall():
		return
	player.try_air_moves()
