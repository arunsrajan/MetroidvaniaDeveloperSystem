@tool
class_name MDSMoveParallel
extends MDSMove
## Its moves all at once: a flight while it fires, a dash that leaves a trail. Done when all are, or
## as soon as the first is ([member until_first]).

@export var moves: Array[MDSMove] = []
@export var until_first := false

func get_children_moves() -> Array[MDSMove]:
	return moves

func _start(ctx: MDSMoveContext) -> void:
	var running: Array[MDSMove] = []
	for move in moves:
		if move and move.can_start(ctx):
			move.begin(ctx)
			running.append(move)
	mem(ctx)[&"moves"] = running

func _update(ctx: MDSMoveContext, delta: float) -> Status:
	var running: Array[MDSMove] = mem(ctx)[&"moves"]
	for move in running.duplicate():
		if move.tick(ctx, delta) != Status.RUNNING:
			move.end(ctx)
			running.erase(move)
			if until_first:
				return Status.DONE
	return Status.DONE if running.is_empty() else Status.RUNNING

func _stop(ctx: MDSMoveContext) -> void:
	var running: Array[MDSMove] = mem(ctx).get(&"moves", [] as Array[MDSMove])
	for move in running:
		move.end(ctx)

## A parallel (for code).
static func of(p_moves: Array[MDSMove], p_until_first := false) -> MDSMoveParallel:
	var p := MDSMoveParallel.new()
	p.moves = p_moves
	p.until_first = p_until_first
	return p
