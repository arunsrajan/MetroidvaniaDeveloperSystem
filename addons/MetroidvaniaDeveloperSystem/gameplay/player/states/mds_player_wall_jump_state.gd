@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_wall_jump_state.svg")
class_name MDSPlayerWallJumpState
extends MDSPlayerState
## Kicked off a wall: up and away from it ([member MDSMovementConfig.wall_jump_velocity]), steering
## locked for [member MDSMovementConfig.wall_jump_lock] seconds.

func _init() -> void:
	required_ability = "wall_jump"

func enter(_previous: StringName, data: Dictionary) -> void:
	var side := int(data.get("side", player.wall_side()))
	var away := -side if side != 0 else -player.facing
	player.velocity = Vector2(player.config.wall_jump_velocity.x * away, player.config.wall_jump_velocity.y)
	player.facing = away
	player.steer_lock_left = player.config.wall_jump_lock
	player.buffer.consume("jump")
	player.jumped.emit()

func physics_update(delta: float) -> void:
	run(delta)
	fall(delta)
	player.move()
	if player.velocity.y >= 0.0 and land_or_fall():
		return
	if machine.time_in_state > player.config.wall_jump_lock and player.try_air_moves():
		return
	if player.velocity.y >= 0.0:
		go(&"Fall")
