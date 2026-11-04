@tool
class_name MDSMoveRepeat
extends MDSMove
## Its move again and again: [member times], or until its [member MDSMove.cancel_when] holds.

@export var move: MDSMove
## 0: forever (stop it with [member MDSMove.cancel_when]).
@export var times := 2

func get_children_moves() -> Array[MDSMove]:
	return [move] if move else []

func _start(ctx: MDSMoveContext) -> void:
	mem(ctx)[&"done"] = 0
	if move:
		move.begin(ctx)

func _update(ctx: MDSMoveContext, delta: float) -> Status:
	if not move:
		return Status.DONE
	var status := move.tick(ctx, delta)
	if status == Status.RUNNING:
		return Status.RUNNING
	move.end(ctx)
	if status == Status.FAILED:
		return Status.FAILED
	var m := mem(ctx)
	m[&"done"] = int(m[&"done"]) + 1
	if times > 0 and int(m[&"done"]) >= times:
		return Status.DONE
	move.begin(ctx)
	return Status.RUNNING

func _stop(ctx: MDSMoveContext) -> void:
	if move:
		move.end(ctx)

## A repeat (for code).
static func of(p_move: MDSMove, p_times := 2) -> MDSMoveRepeat:
	var r := MDSMoveRepeat.new()
	r.move = p_move
	r.times = p_times
	return r
