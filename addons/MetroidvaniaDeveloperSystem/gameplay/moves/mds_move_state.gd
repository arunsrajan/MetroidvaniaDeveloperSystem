class_name MDSMoveState
extends MDSEnemyState
## A state that runs moves: what any enemy needs to fight with them. It runs [member moves] over and
## over, and [method pending] first. Reactions cut in while their conditions hold. Leaving the state
## (a stagger, death) stops whatever was going on.

## What it runs.
var moves: MDSMove
## Moves that cut in ([member MDSMovePhase.reactions]).
var reactions: Array[MDSMove] = []
## The state's memory of the fight.
var ctx: MDSMoveContext

const REPORT_EVERY := 0.1

var _current: MDSMove
var _report_in := 0.0
var _queue: Array[MDSMove] = []

## A state named [param state_name] running [param p_moves].
static func make(state_name: StringName, p_moves: MDSMove = null) -> MDSMoveState:
	var s := MDSMoveState.new()
	s.name = String(state_name)
	s.moves = p_moves
	return s

func _context() -> MDSMoveContext:
	if not ctx:
		ctx = MDSMoveContext.new(enemy)
	return ctx

## [param move] runs next, once.
func pending(move: MDSMove) -> void:
	if move:
		_queue.append(move)

func exit(next: StringName) -> void:
	_stop_current()
	_context().interrupted()
	if EngineDebugger.is_active():
		EngineDebugger.send_message(MDSMoveTree.MESSAGE, [MDSMoveTree.snapshot(self, next)])

## Tells the Fight editor what it is doing, while the editor is running the game.
func _report(delta: float) -> void:
	if not EngineDebugger.is_active():
		return
	_report_in -= delta
	if _report_in <= 0.0:
		_report_in = REPORT_EVERY
		EngineDebugger.send_message(MDSMoveTree.MESSAGE, [MDSMoveTree.snapshot(self)])

func _stop_current() -> void:
	if _current:
		_current.end(_context())
		_current = null

func physics_update(delta: float) -> void:
	_report(delta)
	var c := _context()
	if c.locks <= 0 and _current not in reactions:
		for r in reactions:
			if r and r != _current and not r.when.is_empty() and r.can_start(c):
				_stop_current()
				c.interrupted()
				_current = r
				r.begin(c)
				break
	if not _current:
		_current = _queue.pop_front() if not _queue.is_empty() else moves
		if _current and not _current.can_start(c):
			_current = null
		if _current:
			_current.begin(c)
	if not _current:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()
		return
	var status := c.step(_current, delta)
	if status != MDSMove.Status.RUNNING:
		_stop_current()
