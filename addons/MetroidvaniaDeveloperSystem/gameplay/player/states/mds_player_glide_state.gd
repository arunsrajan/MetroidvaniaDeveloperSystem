@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_glide_state.svg")
class_name MDSPlayerGlideState
extends MDSPlayerState
## With [code]glide[/code]: falling with jump held, the player glides down slowly
## ([member MDSMovementConfig.glide_fall_speed]) and steers; letting go of jump ends it.

func _init() -> void:
	required_ability = "glide"
	trigger = Trigger.AIR
	priority = 20

func can_enter() -> bool:
	return super() and not player.is_on_floor() and player.velocity.y > 40.0 and player.held(&"jump") and not player.in_water()

func physics_update(delta: float) -> void:
	run(delta)
	player.velocity.y = move_toward(player.velocity.y, player.config.glide_fall_speed, player.config.gravity * 2.0 * delta)
	player.move()
	if land_or_fall():
		return
	if not player.held(&"jump"):
		go(&"Fall")
		return
	player.try_air_moves()
