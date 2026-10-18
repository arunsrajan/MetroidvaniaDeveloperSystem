@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_climb_state.svg")
class_name MDSPlayerClimbState
extends MDSPlayerState
## With [code]climb[/code]: on a ladder or vine ([MDSClimbable]), up or down climbs it, free of
## gravity ([member MDSMovementConfig.climb_speed]); jump leaps off it.

func _init() -> void:
	required_ability = "climb"
	trigger = Trigger.ANY
	priority = 45

func can_enter() -> bool:
	return super() and player.get_climbable() != null and absf(player.input_y()) > 0.5 and not (player.is_on_floor() and player.input_y() > 0.5)

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.velocity = Vector2.ZERO
	player.on_landed()

func physics_update(_delta: float) -> void:
	player.velocity = Vector2(player.input_x() * player.config.climb_speed * 0.6, player.input_y() * player.config.climb_speed)
	player.move()
	if player.pressed("jump"):
		player.coyote_left = player.config.coyote_time
		machine.force(&"Jump")
		return
	if player.get_climbable() == null:
		go(&"Fall")
	elif player.is_on_floor() and player.input_y() > 0.5:
		go(&"Idle")
