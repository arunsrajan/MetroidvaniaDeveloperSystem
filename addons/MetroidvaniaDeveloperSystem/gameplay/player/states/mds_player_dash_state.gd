@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_dash_state.svg")
class_name MDSPlayerDashState
extends MDSPlayerState
## With [code]dash[/code]: a burst along the ground ([member MDSMovementConfig.dash_speed] for
## [member MDSMovementConfig.dash_time] s), then [member MDSMovementConfig.dash_cooldown] s before
## the next.

func _init() -> void:
	required_ability = "dash"
	trigger = Trigger.GROUND
	priority = 30

var _dir := 1

func can_enter() -> bool:
	return super() and player.pressed("dash") and player.dash_cooldown_left <= 0.0 and player.is_on_floor() and player.input_y() < 0.5

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.buffer.consume("dash")
	var x := player.input_x()
	_dir = (1 if x > 0.0 else -1) if absf(x) > 0.3 else player.facing
	player.facing = _dir
	player.velocity = Vector2(player.config.dash_speed * _dir, 0.0)

func exit(_next: StringName) -> void:
	player.dash_cooldown_left = player.config.dash_cooldown
	player.velocity.x = clampf(player.velocity.x, -player.config.max_run_speed, player.config.max_run_speed)

func physics_update(_delta: float) -> void:
	player.velocity = Vector2(player.config.dash_speed * _dir, 0.0)
	player.move()
	if machine.time_in_state < player.config.dash_time and not player.is_on_wall():
		return
	if not land_or_fall():
		go(&"Fall")
