@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_glide_state.svg")
class_name MDSPlayerGlideState
extends MDSPlayerState
## With [code]glide[/code]: falling with jump held, the player glides down slowly
## ([member MDSMovementConfig.glide_fall_speed]) and steers; letting go of jump ends it. With
## [member toggled] (the options' "Glide: press to toggle") a jump press while falling starts it and
## the next one ends it, so jump needn't be held.

## Glide starts and ends with a jump press instead of being held ([MDSOptions] sets it).
static var toggled := false

func _init() -> void:
	required_ability = "glide"
	trigger = Trigger.AIR
	priority = 20

func can_enter() -> bool:
	if not super() or player.is_on_floor() or player.velocity.y <= 40.0 or player.in_water():
		return false
	return player.pressed("jump") if toggled else player.held(&"jump")

func enter(_previous: StringName, _data: Dictionary) -> void:
	if toggled:
		player.buffer.consume("jump")

func physics_update(delta: float) -> void:
	run(delta)
	player.velocity.y = move_toward(player.velocity.y, player.config.glide_fall_speed, player.config.gravity * 2.0 * delta)
	player.move()
	if land_or_fall():
		return
	if toggled:
		# A press: a double jump when there is one, else the glide ends.
		if player.try_air_moves():
			return
		if player.pressed("jump"):
			player.buffer.consume("jump")
			go(&"Fall")
		return
	if not player.held(&"jump"):
		go(&"Fall")
		return
	player.try_air_moves()
