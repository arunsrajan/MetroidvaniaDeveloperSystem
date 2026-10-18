@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_state.svg")
class_name MDSState
extends Node
## A state of an [MDSStateMachine]: a child of it, named after the state ("Idle", "Dash").
## Override the virtuals; [member body] is what the machine drives (the player, an enemy) and
## [member machine] the machine itself. Only the current state's [method physics_update],
## [method update] and [method handle_input] run.

## What the machine drives (its [member MDSStateMachine.body]).
var body: Node
var machine: MDSStateMachine

## Called when the state becomes current, from [param previous] (empty at the start), with the
## [param data] given to [method MDSStateMachine.transition_to].
func enter(_previous: StringName, _data: Dictionary) -> void:
	pass

## Called when another state takes over.
func exit(_next: StringName) -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func handle_input(_event: InputEvent) -> void:
	pass

## Whether the machine may enter this state now (an ability state: whether it is owned).
func can_enter() -> bool:
	return true

## Asks the machine to go to [param state] (see [method MDSStateMachine.transition_to]).
func go(state: StringName, data := {}) -> bool:
	return machine.transition_to(state, data) if machine else false
