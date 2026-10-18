@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_input_buffer.svg")
class_name MDSInputBuffer
extends Node
## Remembers presses for a moment, so a jump pressed just before landing still jumps, and a dash or
## an attack pressed during another move still happens after it. [MDSPlayer] calls
## [method record] every physics frame, before its states run; states ask [method has] and
## [method consume].

## The actions it remembers.
@export var actions: PackedStringArray = ["jump", "dash", "attack", "special", "grapple"]
## How long (s) a press is remembered when the asker gives no time of its own.
@export var default_window := 0.12

var _pressed_at: Dictionary = {} ## action -> time (s) of the last press not used yet
var _now := 0.0

## Notes the presses of this physics frame ([param delta]: its length). With [param enabled]
## false (input off), nothing is noted.
func record(delta: float, enabled := true) -> void:
	_now += delta
	if not enabled:
		return
	for a in actions:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a):
			_pressed_at[a] = _now

## Notes a press of [param action] now (for code, AI and tests).
func press(action: String) -> void:
	_pressed_at[action] = _now

## Whether [param action] was pressed in the last [param window] seconds (-1: the default) and
## not used yet.
func has(action: String, window := -1.0) -> bool:
	if not _pressed_at.has(action):
		return false
	return _now - float(_pressed_at[action]) <= (default_window if window < 0.0 else window) + 0.0001

## Uses the press of [param action] up (it does no more).
func consume(action: String) -> void:
	_pressed_at.erase(action)

## Forgets every press.
func clear() -> void:
	_pressed_at.clear()
