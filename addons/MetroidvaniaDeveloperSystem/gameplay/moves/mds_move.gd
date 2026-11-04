@tool
class_name MDSMove
extends Resource
## One thing an enemy does in a fight: a lunge, a volley, a wait. Moves are resources, so they are
## set in the inspector and shared between enemies: what one enemy is doing with a move is kept in
## its [MDSMoveContext] ([method mem]), never here. [MDSMoveSequence], [MDSMovePick],
## [MDSMoveRepeat] and [MDSMoveParallel] hold other moves, so a whole fight is one tree of them, run
## by an [MDSMoveBoss], an [MDSMoveEnemy] or any enemy with an [MDSMoveState].
##
## To add your own, extend this and override [method _start], [method _update] and [method _stop].

enum Status { RUNNING, DONE, FAILED }
## A place in the fight, for what moves there or appears there ([method MDSMoveContext.point]).
enum Anchor { PLAYER, ABOVE_PLAYER, BEHIND_PLAYER, FRONT_OF_PLAYER, SELF, HOME, ARENA_CENTER, ARENA_LEFT, ARENA_RIGHT, ARENA_FAR_SIDE, ARENA_NEAR_SIDE, CEILING_ABOVE_PLAYER, CEILING_ABOVE_SELF, FLOOR_AT_PLAYER, FLOOR_AT_SELF, FLOOR_AT_CENTER }

## A name for the editor and the debug log.
@export var title := ""
## It can only be picked while all of these hold.
@export var when: Array[MDSMoveCondition] = []
## It stops at once when any of these holds (a third swing cut short).
@export var cancel_when: Array[MDSMoveCondition] = []
## How likely [MDSMovePick] is to pick it, against the others.
@export_range(0.0, 100.0, 0.1, "or_greater") var weight := 1.0
## Seconds before it can be picked again.
@export_range(0.0, 60.0, 0.1, "or_greater") var cooldown := 0.0
## Played on the enemy's AnimationPlayer when it starts, if it has that animation.
@export var animation: StringName = &""
## Off: a reaction ([member MDSMovePhase.reactions]) waits for it to end.
@export var interruptible := true
@export_group("Its hit")
## Damage of its hit, without an [member attack] (0: harmless).
@export var damage := 1
## Its hit in full, with its effects. Empty: a plain one of [member damage].
@export var attack: MDSAttackData

## Whether it can start now.
func can_start(ctx: MDSMoveContext) -> bool:
	if ctx.cooling(self):
		return false
	for c in when:
		if c and not c.holds(ctx):
			return false
	return true

## Starts it. Called by what holds it, then [method tick] each frame, then [method end].
func begin(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	m.clear()
	m[&"t"] = 0.0
	m[&"running"] = true
	if not interruptible:
		ctx.locks += 1
	ctx.play(animation)
	_start(ctx)

## One frame of it.
func tick(ctx: MDSMoveContext, delta: float) -> Status:
	for c in cancel_when:
		if c and c.holds(ctx):
			return Status.FAILED
	var m := mem(ctx)
	m[&"t"] = float(m.get(&"t", 0.0)) + delta * ctx.speed()
	return _update(ctx, delta)

## Stops it, however it went.
func end(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	if not m.get(&"running", false):
		return
	m[&"running"] = false
	if not interruptible:
		ctx.locks = maxi(0, ctx.locks - 1)
	_stop(ctx)
	if cooldown > 0.0:
		ctx.cool(self, cooldown)

## What this enemy keeps about this move, for this run of it.
func mem(ctx: MDSMoveContext) -> Dictionary:
	return ctx.memory(self)

## Seconds it has run, sped up by the phase.
func elapsed(ctx: MDSMoveContext) -> float:
	return float(mem(ctx).get(&"t", 0.0))

## Its hit, styled as the enemy's.
func get_attack(ctx: MDSMoveContext) -> MDSAttackData:
	var a := attack
	if not a:
		a = MDSAttackData.make(title if not title.is_empty() else "move", damage, [])
		a.knockback = Vector2(320, -260)
	return ctx.enemy.style_attack(a)

## The moves it holds (for tools).
func get_children_moves() -> Array[MDSMove]:
	return []

func _start(_ctx: MDSMoveContext) -> void:
	pass

func _update(_ctx: MDSMoveContext, _delta: float) -> Status:
	return Status.DONE

func _stop(_ctx: MDSMoveContext) -> void:
	pass
