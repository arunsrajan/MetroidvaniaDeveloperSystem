@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_run_state.svg")
class_name MDSPlayerRunState
extends MDSPlayerState
## Running on the ground.

func physics_update(delta: float) -> void:
	run(delta)
	fall(delta)
	player.move()
	if not player.is_on_floor():
		player.coyote_left = player.config.coyote_time
		go(&"Fall")
		return
	if player.try_ground_moves():
		return
	if absf(player.input_x()) <= 0.01 and absf(player.velocity.x) < 10.0:
		go(&"Idle")
