@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_enemy.svg")
class_name MDSMoveEnemy
extends MDSEnemy
## An ordinary enemy that fights with moves ([MDSMove]): it waits until it sees the player, then runs
## [member moves]. Inherit it and override [method _make_moves] to build them in code.

signal move_cue(cue: StringName)

## What it does in a fight, usually an [MDSMovePick] of its attacks.
@export var moves: MDSMove
## It waits to see the player. Off: it starts at once.
@export var wait_to_see := true

## Its moves, when [member moves] is empty.
func _make_moves() -> MDSMove:
	return MDSMoveWait.of(0.5)

func _make_states() -> Array[Node]:
	var fight := MDSMoveState.make(&"Fight", moves if moves else _make_moves())
	resume_state = &"Fight"
	if not wait_to_see:
		return [fight]
	return [Waiting.new().named(), fight]

class Waiting extends MDSEnemyState:
	func named() -> Waiting:
		name = "Waiting"
		return self
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()
		if enemy.sees_player():
			go(&"Fight")
