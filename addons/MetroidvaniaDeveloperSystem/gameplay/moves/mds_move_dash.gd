@tool
class_name MDSMoveDash
extends MDSMove
## It rushes in a line: a lunge, a swoop that skids along the ground, a retreat, a whirlwind that
## bounces off the walls. It hits on the way when it has [member hit_size].

enum Aim { TOWARD_PLAYER, AWAY_FROM_PLAYER, FORWARD, BACKWARD, AT_PLAYER, ANGLE }

@export var aim: Aim = Aim.TOWARD_PLAYER
## ANGLE: degrees, 0 forward, 90 straight down.
@export_range(-180.0, 180.0, 1.0) var angle := 45.0
@export_range(0.0, 3000.0, 10.0, "or_greater") var speed := 700.0
## Seconds of the rush.
@export_range(0.0, 10.0, 0.05, "or_greater") var seconds := 0.5
## Seconds it holds still first, aimed: the warning.
@export_range(0.0, 10.0, 0.05, "or_greater") var windup := 0.3
## It still falls during the rush (a dash along the ground). Off: it flies straight.
@export var keep_gravity := true
## A rush reaching the floor skids along it for this long.
@export_range(0.0, 10.0, 0.05, "or_greater") var skid := 0.0
## How many times it comes back off a wall.
@export var bounces := 0
## It stops at a wall. Off: it presses on until its time is up.
@export var stop_at_wall := true
## Its hit, this big (none: it only moves).
@export var hit_size := Vector2.ZERO
## Camera shake when it stops at a wall (pixels).
@export var wall_shake := 0.0

func _start(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	m[&"dir"] = Vector2.ZERO
	m[&"bounced"] = 0
	m[&"armed"] = false
	m[&"skid"] = -1.0
	_aim(ctx)

func _aim(ctx: MDSMoveContext) -> void:
	var e := ctx.enemy
	var dir := Vector2(e.facing, 0)
	var at_player := (ctx.player_position() - e.global_position).normalized()
	match aim:
		Aim.TOWARD_PLAYER:
			e.face_player()
			dir = Vector2(e.facing, 0)
		Aim.AWAY_FROM_PLAYER:
			e.face_player()
			dir = Vector2(-e.facing, 0)
		Aim.BACKWARD:
			dir = Vector2(-e.facing, 0)
		Aim.AT_PLAYER:
			dir = at_player if at_player != Vector2.ZERO else dir
			e.facing = 1 if dir.x >= 0.0 else -1
		Aim.ANGLE:
			dir = Vector2.RIGHT.rotated(deg_to_rad(angle))
			dir.x *= e.facing
	mem(ctx)[&"dir"] = dir

func _update(ctx: MDSMoveContext, delta: float) -> Status:
	var e := ctx.enemy
	var m := mem(ctx)
	var t := elapsed(ctx)
	if t < windup:
		ctx.claim(not e.uses_gravity)
		e.velocity = Vector2(0, e.velocity.y if e.uses_gravity else 0.0)
		_aim(ctx)
		return Status.RUNNING
	if not m[&"armed"]:
		m[&"armed"] = true
		if hit_size != Vector2.ZERO:
			var a := get_attack(ctx)
			ctx.arm(a, hit_size)
			MDSAttackFX.on_swing(a, e, float(e.facing), MDSAttackFX.Team.ENEMY)
	var dir: Vector2 = m[&"dir"]
	var fast := speed * ctx.speed()
	var skid_at: float = m[&"skid"]
	if skid_at < 0.0 and skid > 0.0 and dir.y > 0.0 and e.is_on_floor():
		skid_at = t
		m[&"skid"] = t
		dir = Vector2(signf(dir.x) if dir.x != 0.0 else float(e.facing), 0)
		m[&"dir"] = dir
	ctx.claim(not keep_gravity)
	e.velocity = dir * fast if not keep_gravity else Vector2(dir.x * fast, e.velocity.y)
	if dir.x != 0.0 and e.is_on_wall() and signf(e.get_wall_normal().x) == -signf(dir.x):
		if int(m[&"bounced"]) < bounces:
			m[&"bounced"] = int(m[&"bounced"]) + 1
			dir.x = -dir.x
			m[&"dir"] = dir
			e.facing = 1 if dir.x >= 0.0 else -1
			e.velocity.x = dir.x * fast
		elif stop_at_wall:
			_shake(ctx)
			return Status.DONE
	if skid_at >= 0.0:
		return Status.DONE if t - skid_at >= skid else Status.RUNNING
	# A dive that hasn't reached the ground keeps going while it can skid.
	if t >= windup + seconds and (skid <= 0.0 or dir.y <= 0.0 or t >= windup + seconds + 2.0):
		return Status.DONE
	return Status.RUNNING

func _shake(ctx: MDSMoveContext) -> void:
	if wall_shake > 0.0:
		MDSMoveCue.shake(ctx, wall_shake, 0.3)

func _stop(ctx: MDSMoveContext) -> void:
	ctx.disarm()

## A dash (for code).
static func of(p_aim: Aim, p_speed: float, p_seconds: float, p_windup := 0.3, p_hit_size := Vector2.ZERO, p_damage := 1) -> MDSMoveDash:
	var d := MDSMoveDash.new()
	d.aim = p_aim
	d.speed = p_speed
	d.seconds = p_seconds
	d.windup = p_windup
	d.hit_size = p_hit_size
	d.damage = p_damage
	return d
