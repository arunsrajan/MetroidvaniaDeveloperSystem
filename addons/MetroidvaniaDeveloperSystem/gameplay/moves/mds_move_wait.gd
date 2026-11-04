@tool
class_name MDSMoveWait
extends MDSMove
## It stands still for a moment: the rest between attacks, the opening after one.

@export_range(0.0, 10.0, 0.05, "or_greater") var seconds := 0.6
## Up to this much longer, at random.
@export_range(0.0, 10.0, 0.05, "or_greater") var extra := 0.0
## It keeps facing the player.
@export var face_player := true

func _start(ctx: MDSMoveContext) -> void:
	mem(ctx)[&"for"] = seconds + ctx.rng.randf() * extra

func _update(ctx: MDSMoveContext, _delta: float) -> Status:
	if face_player:
		ctx.enemy.face_player()
	return Status.DONE if elapsed(ctx) >= float(mem(ctx)[&"for"]) else Status.RUNNING

## A wait (for code).
static func of(p_seconds: float, p_extra := 0.0) -> MDSMoveWait:
	var w := MDSMoveWait.new()
	w.seconds = p_seconds
	w.extra = p_extra
	return w
