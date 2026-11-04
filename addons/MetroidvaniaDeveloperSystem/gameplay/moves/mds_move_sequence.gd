@tool
class_name MDSMoveSequence
extends MDSMove
## Its moves one after another: a triple cut, a leap into a lunge. A move that can't start or fails
## ends it, unless [member keep_going].

@export var moves: Array[MDSMove] = []
## A move that fails or can't start is skipped.
@export var keep_going := false

func get_children_moves() -> Array[MDSMove]:
	return moves

func _start(ctx: MDSMoveContext) -> void:
	mem(ctx)[&"i"] = -1

func _update(ctx: MDSMoveContext, delta: float) -> Status:
	var m := mem(ctx)
	var i: int = m[&"i"]
	if i >= 0 and i < moves.size():
		var status := moves[i].tick(ctx, delta)
		if status == Status.RUNNING:
			return Status.RUNNING
		moves[i].end(ctx)
		if status == Status.FAILED and not keep_going:
			m[&"i"] = -2
			return Status.FAILED
	return _next(ctx)

## Starts the next move. It runs from the next frame.
func _next(ctx: MDSMoveContext) -> Status:
	var m := mem(ctx)
	var i: int = m[&"i"] + 1
	while i < moves.size():
		var move := moves[i]
		if move and move.can_start(ctx):
			m[&"i"] = i
			move.begin(ctx)
			return Status.RUNNING
		if move and not keep_going:
			m[&"i"] = -2
			return Status.FAILED
		i += 1
	m[&"i"] = -2
	return Status.DONE

func _stop(ctx: MDSMoveContext) -> void:
	var i: int = mem(ctx).get(&"i", -1)
	if i >= 0 and i < moves.size():
		moves[i].end(ctx)

## A sequence (for code).
static func of(p_moves: Array[MDSMove], p_title := "") -> MDSMoveSequence:
	var s := MDSMoveSequence.new()
	s.moves = p_moves
	s.title = p_title
	return s
