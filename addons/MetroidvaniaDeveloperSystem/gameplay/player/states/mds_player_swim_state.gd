@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_swim_state.svg")
class_name MDSPlayerSwimState
extends MDSPlayerState
## With [code]swim[/code]: in water ([MDSSwimZone]) the player swims freely
## ([member MDSMovementConfig.swim_speed]) instead of sinking; jump at the surface leaps out.

func _init() -> void:
	required_ability = "swim"
	trigger = Trigger.ANY
	priority = 70

func can_enter() -> bool:
	return super() and player.in_water()

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.velocity *= 0.4
	player.on_landed()

func physics_update(delta: float) -> void:
	var want := Vector2(player.input_x(), player.input_y()) * player.config.swim_speed
	if absf(player.input_x()) > 0.01:
		player.facing = 1 if player.input_x() > 0.0 else -1
	player.velocity = player.velocity.move_toward(want, player.config.swim_speed * 4.0 * delta)
	player.velocity.y += player.config.swim_gravity * 0.1 * delta
	player.move()
	if not player.in_water():
		if player.held(&"jump") or player.input_y() < -0.5:
			player.velocity.y = minf(player.velocity.y, -player.config.jump_velocity * 0.8)
			machine.force(&"Jump", {"keep_velocity": true})
		else:
			go(&"Fall")
