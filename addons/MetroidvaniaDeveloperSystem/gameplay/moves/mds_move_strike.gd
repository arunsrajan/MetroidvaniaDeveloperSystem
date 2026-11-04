@tool
class_name MDSMoveStrike
extends MDSMove
## One swing: it winds up, its hit is on for a moment, then it recovers, which is the player's
## opening. Chain them in an [MDSMoveSequence] for a double or triple cut, with a move between to
## follow the player.

@export_range(0.0, 10.0, 0.01, "or_greater") var windup := 0.3
@export_range(0.01, 10.0, 0.01, "or_greater") var active := 0.15
@export_range(0.0, 10.0, 0.01, "or_greater") var recovery := 0.3
## Its hit, in front of it...
@export var size := Vector2(110, 70)
## ...this far from its middle, facing right. Y below 0 is up.
@export var offset := Vector2(70, 0)
## Its hit reaches down to the floor, however far that is (a swipe from the ceiling).
@export var reach_floor := false
## It steps forward as it swings, at this speed.
@export_range(0.0, 2000.0, 10.0, "or_greater") var step := 0.0
## It turns to the player as it winds up.
@export var face_player := true
## How it looks while it winds up: the warning (transparent: as it is).
@export var windup_tint := Color(1.0, 0.55, 0.45, 1.0)

func _start(ctx: MDSMoveContext) -> void:
	mem(ctx)[&"armed"] = false
	if face_player:
		ctx.enemy.face_player()
	mem(ctx)[&"modulate"] = ctx.enemy.modulate
	if windup_tint.a > 0.0 and windup > 0.0:
		ctx.enemy.modulate = Color(windup_tint, ctx.enemy.modulate.a)

func _update(ctx: MDSMoveContext, _delta: float) -> Status:
	var e := ctx.enemy
	var m := mem(ctx)
	var t := elapsed(ctx)
	if t < windup:
		if face_player:
			e.face_player()
		return Status.RUNNING
	if not m[&"armed"]:
		m[&"armed"] = true
		e.modulate = m[&"modulate"]
		var a := get_attack(ctx)
		var box_size := size
		var box_offset := offset
		if reach_floor:
			var top := e.global_position.y + offset.y - size.y * 0.5
			box_size.y = maxf(size.y, ctx.floor_at(e.global_position).y - top)
			box_offset.y = top + box_size.y * 0.5 - e.global_position.y
		ctx.arm(a, box_size, box_offset)
		MDSAttackFX.on_swing(a, e, float(e.facing), MDSAttackFX.Team.ENEMY)
	if t < windup + active:
		if step > 0.0:
			ctx.claim()
			e.velocity.x = e.facing * step * ctx.speed()
		return Status.RUNNING
	ctx.disarm()
	return Status.DONE if t >= windup + active + recovery else Status.RUNNING

func _stop(ctx: MDSMoveContext) -> void:
	ctx.disarm()
	var m := mem(ctx)
	if m.has(&"modulate"):
		ctx.enemy.modulate = m[&"modulate"]

## A strike (for code).
static func of(p_windup: float, p_size: Vector2, p_offset: Vector2, p_damage := 1, p_recovery := 0.3, p_step := 0.0) -> MDSMoveStrike:
	var s := MDSMoveStrike.new()
	s.windup = p_windup
	s.size = p_size
	s.offset = p_offset
	s.damage = p_damage
	s.recovery = p_recovery
	s.step = p_step
	return s
