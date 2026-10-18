@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_ledge_grab_state.svg")
class_name MDSPlayerLedgeGrabState
extends MDSPlayerState
## With [code]ledge_grab[/code]: falling past the top of a wall it faces, the player catches its
## edge and hangs there. Up or jump climbs on (LedgeClimb), down or away lets go.

func _init() -> void:
	required_ability = "ledge_grab"
	trigger = Trigger.AIR
	priority = 35

## The top of the ledge held (global).
var ledge := Vector2.INF
var side := 1

func can_enter() -> bool:
	if not super() or player.is_on_floor() or player.velocity.y < 0.0:
		return false
	var s := player.wall_side()
	if s == 0 or signf(player.input_x()) == -s:
		return false
	return find_ledge(s) != Vector2.INF

## The top of the wall on side [param s], if the player's hands are at it (INF: none).
func find_ledge(s: int) -> Vector2:
	player.ledge_check.target_position = Vector2(s * (player.body_size.x * 0.5 + 10), 0)
	player.ledge_check.force_raycast_update()
	if player.ledge_check.is_colliding():
		return Vector2.INF
	var space := player.get_world_2d().direct_space_state
	var top := player.global_position + Vector2(s * (player.body_size.x * 0.5 + 6), -player.body_size.y * 0.5 - 8)
	var q := PhysicsRayQueryParameters2D.create(top, top + Vector2(0, player.body_size.y * 0.5), MDSGameplaySetup.bit("world"), [player.get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector2).y > -0.7:
		return Vector2.INF
	return hit.position

func enter(_previous: StringName, _data: Dictionary) -> void:
	side = player.wall_side()
	ledge = find_ledge(side)
	player.facing = side
	player.velocity = Vector2.ZERO
	if ledge != Vector2.INF:
		player.global_position.y = ledge.y + player.body_size.y * 0.5 - 6.0
	player.air_dashes_left = player.config.air_dashes
	player.air_jumps_left = player.config.max_air_jumps if player.has_ability("double_jump") else 0

func physics_update(_delta: float) -> void:
	player.velocity = Vector2.ZERO
	if player.input_y() < -0.5 or player.pressed("jump"):
		player.buffer.consume("jump")
		machine.force(&"LedgeClimb", {"ledge": ledge, "side": side})
	elif player.input_y() > 0.5 or signf(player.input_x()) == -side:
		player.global_position.x -= side * 2.0
		go(&"Fall")
