@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_ledge_climb_state.svg")
class_name MDSPlayerLedgeClimbState
extends MDSPlayerState
## Climbing up onto a ledge held by LedgeGrab: the player rises over its edge onto the top, then
## stands.

func _init() -> void:
	required_ability = "ledge_grab"

## Seconds the climb takes.
@export var climb_time := 0.18
var _from := Vector2.ZERO
var _to := Vector2.ZERO

func enter(_previous: StringName, data: Dictionary) -> void:
	var ledge: Vector2 = data.get("ledge", player.global_position)
	var side := int(data.get("side", player.facing))
	_from = player.global_position
	_to = Vector2(ledge.x + side * (player.body_size.x * 0.5 + 2.0), ledge.y - player.body_size.y * 0.5 - 1.0)
	player.velocity = Vector2.ZERO

func physics_update(_delta: float) -> void:
	var t := clampf(machine.time_in_state / climb_time, 0.0, 1.0)
	player.global_position = _from.lerp(Vector2(_from.x, _to.y), minf(1.0, t * 2.0)).lerp(_to, maxf(0.0, t * 2.0 - 1.0))
	if t >= 1.0:
		player.velocity = Vector2.ZERO
		player.on_landed()
		go(&"Idle")
