@tool
class_name MDSMoveFly
extends MDSMove
## It flies to a place: over the player, up to the ceiling, back to the middle of its area. Gravity
## doesn't hold it while it does. It ends on arriving, or when its time is up.

@export var target: MDSMove.Anchor = MDSMove.Anchor.ABOVE_PLAYER
@export var offset := Vector2.ZERO
@export_range(0.0, 3000.0, 10.0, "or_greater") var speed := 500.0
## Close enough, in pixels.
@export_range(1.0, 200.0, 1.0) var arrive_within := 12.0
## It gives up after this long.
@export_range(0.1, 20.0, 0.1, "or_greater") var max_seconds := 2.0
## It stays over the moving target until its time is up (hovering over the player).
@export var follow := false
## Its hit on the way, this big (none: it only moves).
@export var hit_size := Vector2.ZERO
## The place at the start stays its goal, wherever the player goes. Off: it keeps tracking.
@export var fix_target := true

func _start(ctx: MDSMoveContext) -> void:
	mem(ctx)[&"to"] = ctx.point(target, offset)
	if hit_size != Vector2.ZERO:
		ctx.arm(get_attack(ctx), hit_size)

func _update(ctx: MDSMoveContext, delta: float) -> Status:
	var e := ctx.enemy
	var m := mem(ctx)
	var to: Vector2 = m[&"to"] if fix_target and not follow else ctx.point(target, offset)
	var away := to - e.global_position
	ctx.claim(true)
	var fast := speed * ctx.speed()
	e.velocity = away.normalized() * minf(fast, away.length() / maxf(delta, 0.001))
	if absf(away.x) > 4.0:
		e.facing = 1 if away.x > 0.0 else -1
	if elapsed(ctx) >= max_seconds:
		return Status.DONE
	if not follow and away.length() <= arrive_within:
		e.velocity = Vector2.ZERO
		return Status.DONE
	return Status.RUNNING

func _stop(ctx: MDSMoveContext) -> void:
	ctx.disarm()

## A flight (for code).
static func of(p_target: MDSMove.Anchor, p_speed := 500.0, p_offset := Vector2.ZERO, p_max_seconds := 2.0) -> MDSMoveFly:
	var f := MDSMoveFly.new()
	f.target = p_target
	f.speed = p_speed
	f.offset = p_offset
	f.max_seconds = p_max_seconds
	return f
