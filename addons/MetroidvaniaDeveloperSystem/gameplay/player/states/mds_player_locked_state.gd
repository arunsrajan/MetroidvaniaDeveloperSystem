@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_locked_state.svg")
class_name MDSPlayerLockedState
extends MDSPlayerState
## While [MDSWorldGame] changes rooms: no input, no gravity, the velocity left as it is (the game
## gives it back on arrival). It ends with the room change.

func enter(_previous: StringName, _data: Dictionary) -> void:
	if player.attacks and player.attacks.has_method(&"cancel"):
		player.attacks.call(&"cancel")

func physics_update(_delta: float) -> void:
	if player.game and player.game.changing_room:
		return
	machine.force(&"Idle" if player.is_on_floor() else (&"Jump" if player.velocity.y < 0.0 else &"Fall"), {"keep_velocity": true})
