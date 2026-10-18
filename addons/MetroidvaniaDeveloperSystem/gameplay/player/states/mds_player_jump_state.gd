@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_jump_state.svg")
class_name MDSPlayerJumpState
extends MDSPlayerState
## Rising: a jump from the ground (or just after walking off it: coyote time), or in the air with
## the [code]double_jump[/code] ability (an air jump). Releasing jump early cuts it short
## ([member MDSMovementConfig.jump_cut_multiplier]). Entered with [code]{keep_velocity: true}[/code]
## (a pogo bounce) it keeps the velocity it is given.

func _init() -> void:
	trigger = Trigger.ANY
	priority = 25

var _cut := false

func can_enter() -> bool:
	if not player or not player.pressed("jump", player.config.jump_buffer_time):
		return false
	if player.get_body_height() < 1.0 and not player.can_stand():
		return false
	if player.can_ground_jump():
		return true
	return player.has_ability("double_jump") and player.air_jumps_left > 0

func enter(_previous: StringName, data: Dictionary) -> void:
	_cut = false
	if data.get("keep_velocity", false):
		_cut = true
		return
	if not player.can_ground_jump():
		player.air_jumps_left -= 1
	player.jump()

func physics_update(delta: float) -> void:
	run(delta)
	if not _cut and player.velocity.y < 0.0 and not player.held(&"jump"):
		player.velocity.y *= player.config.jump_cut_multiplier
		_cut = true
	fall(delta)
	player.move()
	if player.velocity.y >= 0.0 and land_or_fall():
		return
	if player.try_air_moves():
		return
	if player.velocity.y >= 0.0:
		go(&"Fall")
