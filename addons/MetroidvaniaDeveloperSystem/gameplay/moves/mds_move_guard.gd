@tool
class_name MDSMoveGuard
extends MDSMove
## It stands on guard: hits don't land for [member seconds]. A hit in that time sets off its
## [member riposte], a move of its own (a dash into a flurry, a teleport behind the player).

@export_range(0.05, 10.0, 0.05, "or_greater") var seconds := 0.6
## What it does when it is hit on guard.
@export var riposte: MDSMove
## How it looks on guard.
@export var tint := Color(0.75, 0.85, 1.0, 1.0)

func get_children_moves() -> Array[MDSMove]:
	return [riposte] if riposte else []

func _start(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	m[&"parried"] = false
	m[&"modulate"] = ctx.enemy.modulate
	m[&"blocker"] = ctx.enemy.hurtbox.blocker
	ctx.enemy.modulate = Color(tint, ctx.enemy.modulate.a)
	ctx.enemy.face_player()
	ctx.enemy.hurtbox.blocker = func(_info: MDSDamageInfo) -> bool:
		mem(ctx)[&"parried"] = true
		return true

func _update(ctx: MDSMoveContext, delta: float) -> Status:
	var m := mem(ctx)
	if m.get(&"countering", false):
		return (riposte.tick(ctx, delta))
	if m[&"parried"]:
		_lower(ctx)
		if not riposte:
			return Status.DONE
		m[&"countering"] = true
		riposte.begin(ctx)
		return Status.RUNNING
	return Status.DONE if elapsed(ctx) >= seconds else Status.RUNNING

func _lower(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	if m.has(&"blocker"):
		ctx.enemy.hurtbox.blocker = m[&"blocker"]
		ctx.enemy.modulate = m[&"modulate"]
		m.erase(&"blocker")

func _stop(ctx: MDSMoveContext) -> void:
	_lower(ctx)
	if mem(ctx).get(&"countering", false) and riposte:
		riposte.end(ctx)

## A guard (for code).
static func of(p_seconds: float, p_riposte: MDSMove = null) -> MDSMoveGuard:
	var g := MDSMoveGuard.new()
	g.seconds = p_seconds
	g.riposte = p_riposte
	return g
