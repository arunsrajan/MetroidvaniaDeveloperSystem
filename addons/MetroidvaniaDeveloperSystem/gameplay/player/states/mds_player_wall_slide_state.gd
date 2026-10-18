@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_wall_slide_state.svg")
class_name MDSPlayerWallSlideState
extends MDSPlayerState
## With [code]wall_jump[/code]: falling against a wall while pressing toward it slides down it
## slowly ([member MDSMovementConfig.wall_slide_speed]); jump kicks off it (WallJump).

func _init() -> void:
	required_ability = "wall_jump"
	trigger = Trigger.AIR
	priority = 30

var side := 0

func can_enter() -> bool:
	if not super() or player.is_on_floor() or player.velocity.y < 0.0:
		return false
	var s := player.wall_side()
	return s != 0 and signf(player.input_x()) == s

func enter(_previous: StringName, _data: Dictionary) -> void:
	side = player.wall_side()
	player.facing = side
	player.air_dashes_left = player.config.air_dashes

func physics_update(delta: float) -> void:
	player.velocity.x = side * 60.0
	player.velocity.y = minf(player.velocity.y + player.config.gravity * delta, player.config.wall_slide_speed)
	player.move()
	if land_or_fall():
		return
	if player.pressed("jump"):
		machine.force(&"WallJump", {"side": side})
		return
	if not player.touching_wall(side) or signf(player.input_x()) == -side:
		go(&"Fall")
		return
	player.try_air_moves()
