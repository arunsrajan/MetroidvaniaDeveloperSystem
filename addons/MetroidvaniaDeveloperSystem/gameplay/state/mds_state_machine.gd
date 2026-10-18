@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_state_machine.svg")
class_name MDSStateMachine
extends Node
## A finite state machine shared by the player, enemies and bosses: its [MDSState] children are
## the states, by name. Only the current one runs (its physics_update, update and handle_input).
## [method transition_to] changes state when the target's [method MDSState.can_enter] allows
## it; [method force] changes it anyway (hurt, death, locks).

signal state_changed(from: StringName, to: StringName)

## The state to start in. Empty: the first child state.
@export var initial_state: StringName = &""
## What the states drive. Empty: the machine's parent.
@export var body: Node
## Drive the states from this node's own process callbacks. Off: the body calls
## [method physics_step] (the player does, to order input, states and movement).
@export var self_driven := true

var current: MDSState
var states: Dictionary = {} ## name -> MDSState
## How long (s) the current state has lasted.
var time_in_state := 0.0
var previous_state: StringName = &""

func _ready() -> void:
	if not body:
		body = get_parent()
	for c in get_children():
		register(c)
	if not current:
		var start := initial_state if states.has(initial_state) else (StringName(states.keys()[0]) if not states.is_empty() else &"")
		if not String(start).is_empty():
			force(start)

## Adds [param state] (a child [MDSState]) to the machine.
func register(state: Node) -> void:
	if not state is MDSState:
		return
	var s := state as MDSState
	s.body = body
	s.machine = self
	states[StringName(s.name)] = s

## The current state's name (empty: none).
func get_state() -> StringName:
	return StringName(current.name) if current else &""

## Whether the current state is [param state_name].
func is_in(state_name: StringName) -> bool:
	return current != null and StringName(current.name) == state_name

func has_state(state_name: StringName) -> bool:
	return states.has(state_name)

## Goes to [param state_name] if it exists and its can_enter() allows it. Returns whether it did
## (going to the current state again re-enters it).
func transition_to(state_name: StringName, data := {}) -> bool:
	var s: MDSState = states.get(state_name)
	if not s or not s.can_enter():
		return false
	_switch(s, data)
	return true

## Goes to [param state_name] whatever its can_enter() says.
func force(state_name: StringName, data := {}) -> bool:
	var s: MDSState = states.get(state_name)
	if not s:
		return false
	_switch(s, data)
	return true

func _switch(s: MDSState, data: Dictionary) -> void:
	var from := get_state()
	if current:
		current.exit(StringName(s.name))
	previous_state = from
	current = s
	time_in_state = 0.0
	s.enter(from, data)
	state_changed.emit(from, StringName(s.name))

## One physics step of the current state (called by the body when not [member self_driven]).
func physics_step(delta: float) -> void:
	time_in_state += delta
	if current:
		current.physics_update(delta)

func _physics_process(delta: float) -> void:
	if self_driven:
		physics_step(delta)

func _process(delta: float) -> void:
	if current:
		current.update(delta)

func _unhandled_input(event: InputEvent) -> void:
	if current:
		current.handle_input(event)
