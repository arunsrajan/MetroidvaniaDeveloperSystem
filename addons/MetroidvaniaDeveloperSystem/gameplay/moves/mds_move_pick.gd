@tool
class_name MDSMovePick
extends MDSMove
## One of its moves: at random by [member MDSMove.weight], the first that can start, or each in turn.
## Fails when none can start. What it picks can be held back by its [member MDSMove.when] and
## [member MDSMove.cooldown], so a phase's attacks are a pick of them.

enum Mode { RANDOM, FIRST_READY, IN_TURN }

@export var moves: Array[MDSMove] = []
@export var mode: Mode = Mode.RANDOM
## RANDOM: not the same one twice in a row, when there is another.
@export var no_repeat := true

func get_children_moves() -> Array[MDSMove]:
	return moves

func _start(ctx: MDSMoveContext) -> void:
	var move := choose(ctx)
	mem(ctx)[&"move"] = move
	if move:
		move.begin(ctx)

func _update(ctx: MDSMoveContext, delta: float) -> Status:
	var move: MDSMove = mem(ctx).get(&"move")
	return move.tick(ctx, delta) if move else Status.FAILED

func _stop(ctx: MDSMoveContext) -> void:
	var move: MDSMove = mem(ctx).get(&"move")
	if move:
		move.end(ctx)

## The move it picks now (null: none can start).
func choose(ctx: MDSMoveContext) -> MDSMove:
	var keep := ctx.keeps(self)
	var options: Array[MDSMove] = []
	for move in moves:
		if move and move.can_start(ctx):
			options.append(move)
	if options.is_empty():
		return null
	match mode:
		Mode.FIRST_READY:
			return options[0]
		Mode.IN_TURN:
			var at: int = keep.get(&"at", -1)
			for n in moves.size():
				var i := (at + 1 + n) % moves.size()
				if moves[i] in options:
					keep[&"at"] = i
					return moves[i]
	if no_repeat and options.size() > 1:
		options.erase(keep.get(&"last"))
	var total := 0.0
	for move in options:
		total += move.weight
	var roll := ctx.rng.randf() * total
	var chosen: MDSMove = options[-1]
	for move in options:
		roll -= move.weight
		if roll <= 0.0:
			chosen = move
			break
	keep[&"last"] = chosen
	return chosen

## A pick (for code).
static func of(p_moves: Array[MDSMove], p_mode := Mode.RANDOM) -> MDSMovePick:
	var p := MDSMovePick.new()
	p.moves = p_moves
	p.mode = p_mode
	return p
