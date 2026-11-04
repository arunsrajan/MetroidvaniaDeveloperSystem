@tool
class_name MDSMoveLeap
extends MDSMove
## It jumps in an arc: at the player, straight up, to the far side. It ends at the top of the jump,
## ready for an attack in the air, or on landing, where it can slam.

enum EndAt { LANDING, APEX }

@export var target: MDSMove.Anchor = MDSMove.Anchor.PLAYER
@export var offset := Vector2.ZERO
## How high it goes, in pixels above where it left the ground.
@export_range(0.0, 2000.0, 10.0, "or_greater") var height := 260.0
@export var end_at: EndAt = EndAt.LANDING
## Seconds it crouches first: the warning.
@export_range(0.0, 10.0, 0.05, "or_greater") var windup := 0.2
## Pulling it down during the leap. 0: its own gravity.
@export var leap_gravity := 0.0
## Landing, a hit of this size at its feet (none: no slam).
@export var slam_size := Vector2.ZERO
@export_range(0.0, 2.0, 0.01, "or_greater") var slam_time := 0.15
@export var slam_shake := 0.0

func _gravity(ctx: MDSMoveContext) -> float:
	return leap_gravity if leap_gravity > 0.0 else maxf(1.0, ctx.enemy.gravity)

func _start(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	m[&"state"] = 0
	m[&"land"] = 0.0

func _update(ctx: MDSMoveContext, delta: float) -> Status:
	var e := ctx.enemy
	var m := mem(ctx)
	var t := elapsed(ctx)
	match int(m[&"state"]):
		0:
			if t < windup:
				return Status.RUNNING
			var g := _gravity(ctx)
			var rise := sqrt(2.0 * g * height)
			var there := ctx.point(target, offset)
			var air := 2.0 * rise / g
			e.face_player()
			e.velocity = Vector2((there.x - e.global_position.x) / air, -rise)
			m[&"state"] = 1
			m[&"left_at"] = t
			ctx.claim(true)
		1:
			ctx.claim(true)
			e.velocity.y = minf(e.velocity.y + _gravity(ctx) * delta, e.max_fall_speed)
			if end_at == EndAt.APEX and e.velocity.y >= 0.0:
				e.velocity = Vector2.ZERO
				return Status.DONE
			if t - float(m[&"left_at"]) > 0.08 and e.is_on_floor():
				e.velocity.x = 0.0
				if slam_size == Vector2.ZERO:
					return Status.DONE
				ctx.arm(get_attack(ctx), slam_size, Vector2(0, e.body_size.y * 0.5 - slam_size.y * 0.5))
				MDSMoveCue.shake(ctx, slam_shake, 0.3)
				m[&"state"] = 2
				m[&"land"] = t
			elif t - float(m[&"left_at"]) > 4.0:
				return Status.DONE
		2:
			if t - float(m[&"land"]) >= slam_time:
				return Status.DONE
	return Status.RUNNING

func _stop(ctx: MDSMoveContext) -> void:
	ctx.disarm()

## A leap (for code).
static func of(p_target: MDSMove.Anchor, p_height: float, p_end_at := EndAt.LANDING, p_windup := 0.2) -> MDSMoveLeap:
	var l := MDSMoveLeap.new()
	l.target = p_target
	l.height = p_height
	l.end_at = p_end_at
	l.windup = p_windup
	return l
