@tool
class_name MDSMoveVanish
extends MDSMove
## It leaves the fight and comes back elsewhere: under the floorboards, into the void, a teleport
## behind the player. While gone it can't be hit and doesn't hit. HIDE and SHOW split it around other
## moves (it fires from below, then rises): a stagger or death always brings it back.

enum Mode { VANISH_AND_RETURN, HIDE, SHOW }

@export var mode: Mode = Mode.VANISH_AND_RETURN
## Seconds gone (VANISH_AND_RETURN), or until it counts as done (HIDE, SHOW).
@export_range(0.0, 10.0, 0.05, "or_greater") var seconds := 0.6
## Where it comes back.
@export var reappear_at: MDSMove.Anchor = MDSMove.Anchor.FLOOR_AT_PLAYER
@export var offset := Vector2.ZERO
## A mark shown where it will come back, for this long before it does (rattling boards, a ripple).
@export_range(0.0, 10.0, 0.05, "or_greater") var marker_time := 0.4
@export var marker_color := Color(1, 1, 1, 0.5)

func _start(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	m[&"shown"] = false
	if mode != Mode.SHOW:
		ctx.hide_body()

func _update(ctx: MDSMoveContext, _delta: float) -> Status:
	var m := mem(ctx)
	var t := elapsed(ctx)
	if mode == Mode.HIDE:
		return Status.DONE if t >= seconds else Status.RUNNING
	if not m.has(&"at") and t >= maxf(0.0, seconds - marker_time) * (0.0 if mode == Mode.SHOW else 1.0):
		var at := ctx.point(reappear_at, offset)
		m[&"at"] = at
		if marker_time > 0.0:
			var mark := MDSCombatZone.marker(at, Vector2(ctx.enemy.body_size.x * 1.2, 24.0), marker_time / ctx.speed(), marker_color)
			ctx.spawn_parent().add_child(mark)
			mark.global_position = at
			ctx.track(mark)
	if m.has(&"at") and t >= seconds + (marker_time if mode == Mode.SHOW else 0.0):
		ctx.enemy.global_position = m[&"at"]
		ctx.show_body()
		ctx.enemy.face_player()
		m[&"shown"] = true
		return Status.DONE
	return Status.RUNNING

## A vanishing (for code).
static func of(p_mode: Mode, p_seconds: float, p_at := MDSMove.Anchor.FLOOR_AT_PLAYER, p_offset := Vector2.ZERO) -> MDSMoveVanish:
	var v := MDSMoveVanish.new()
	v.mode = p_mode
	v.seconds = p_seconds
	v.reappear_at = p_at
	v.offset = p_offset
	return v
