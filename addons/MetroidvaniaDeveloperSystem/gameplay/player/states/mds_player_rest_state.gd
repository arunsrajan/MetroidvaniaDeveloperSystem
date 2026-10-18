@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_rest_state.svg")
class_name MDSPlayerRestState
extends MDSPlayerState
## Sitting on a bench ([MDSBench]): still until the bench gets the player up.

func enter(_previous: StringName, _data: Dictionary) -> void:
	player.velocity = Vector2.ZERO
	if player.attacks and player.attacks.has_method(&"cancel"):
		player.attacks.call(&"cancel")

func physics_update(_delta: float) -> void:
	player.velocity = Vector2.ZERO
