@tool
class_name MDSMoveShoot
extends MDSMove
## It fires: a fan of shots, three in a row at where the player was, rocks falling from the ceiling
## after a puff of dust, bombs that bounce and go off.

enum From { SELF, CEILING_RANDOM, CEILING_ABOVE_PLAYER, RING_AROUND_SELF }
enum Aim { AT_PLAYER, AT_WHERE_PLAYER_WAS, FORWARD, DOWN, UP, FAN_AT_PLAYER, ALL_AROUND }

@export var from: From = From.SELF
@export var aim: Aim = Aim.AT_PLAYER
@export_range(1, 64, 1, "or_greater") var count := 3
## Seconds between shots (0: all at once).
@export_range(0.0, 5.0, 0.01, "or_greater") var interval := 0.15
## Seconds it holds still before the first shot: the warning.
@export_range(0.0, 10.0, 0.01, "or_greater") var windup := 0.3
## Seconds before it moves on after the last shot.
@export_range(0.0, 10.0, 0.01, "or_greater") var recovery := 0.3
## FAN_AT_PLAYER: degrees between shots.
@export_range(0.0, 90.0, 1.0) var spread := 14.0
@export_range(0.0, 3000.0, 10.0, "or_greater") var speed := 420.0
## Pull down on the shots (an arc).
@export var drop := 0.0
@export var radius := 10.0
@export var color := Color(0.85, 0.5, 1.0)
@export_range(0.1, 30.0, 0.1, "or_greater") var lifetime := 3.0
## They go through terrain.
@export var passes_walls := false
## Shots from the ceiling: seconds of warning at the spot before they fall.
@export_range(0.0, 10.0, 0.01, "or_greater") var marker_time := 0.0
@export_group("Bombs")
## How many times a shot comes back off the terrain.
@export var bounces := 0
## Seconds it sits before it goes off, once it has stopped (0: it isn't a bomb).
@export_range(0.0, 10.0, 0.05, "or_greater") var fuse := 0.0
## The player can knock it away.
@export var knockable := false
## It goes off in a column (off: a row).
@export var burst_vertical := true
@export var burst_size := Vector2(60, 400)

func _start(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	m[&"fired"] = 0
	m[&"was_at"] = ctx.player_position()
	ctx.enemy.face_player()

func _update(ctx: MDSMoveContext, _delta: float) -> Status:
	var m := mem(ctx)
	var t := elapsed(ctx)
	while int(m[&"fired"]) < count and t >= windup + interval * int(m[&"fired"]):
		_fire(ctx, int(m[&"fired"]))
		m[&"fired"] = int(m[&"fired"]) + 1
	return Status.DONE if int(m[&"fired"]) >= count and t >= windup + interval * count + recovery else Status.RUNNING

func _fire(ctx: MDSMoveContext, index: int) -> void:
	var at := _origin(ctx, index)
	if marker_time > 0.0:
		var mark := MDSCombatZone.marker(at, Vector2(radius * 4.0, 16.0), marker_time / ctx.speed(), Color(color, 0.7))
		ctx.spawn_parent().add_child(mark)
		mark.global_position = at
		ctx.track(mark)
		var clears := ctx.clears
		var delay := ctx.enemy.get_tree().create_timer(marker_time / ctx.speed(), false, true)
		delay.timeout.connect(func() -> void:
			if is_instance_valid(ctx.enemy) and not ctx.enemy.dying and ctx.clears == clears:
				_launch(ctx, at, index))
	else:
		_launch(ctx, at, index)

func _launch(ctx: MDSMoveContext, at: Vector2, index: int) -> void:
	var shot := MDSBossShot.new()
	shot.team = MDSHitbox.Team.ENEMY
	shot.attack = get_attack(ctx)
	shot.source = ctx.enemy
	shot.velocity = _direction(ctx, at, index) * speed * ctx.speed()
	shot.drop = drop
	shot.radius = radius
	shot.color = color
	shot.lifetime = lifetime
	shot.bounces = bounces
	shot.fuse = fuse
	shot.knockable = knockable
	shot.burst_vertical = burst_vertical
	shot.burst_size = burst_size
	shot.burst_color = color
	ctx.spawn_parent().add_child(shot)
	shot.global_position = at
	shot.ignore_terrain = passes_walls
	ctx.track(shot)

func _origin(ctx: MDSMoveContext, index: int) -> Vector2:
	var e := ctx.enemy
	var r := ctx.arena_rect()
	match from:
		From.CEILING_RANDOM:
			var hang := ctx.ceiling_at(Vector2(ctx.rng.randf_range(r.position.x + 40.0, r.end.x - 40.0), r.get_center().y))
			return hang + Vector2(0, radius + 4.0)
		From.CEILING_ABOVE_PLAYER:
			var player := ctx.player_position()
			return ctx.ceiling_at(player) + Vector2(ctx.rng.randf_range(-40.0, 40.0), radius + 4.0)
		From.RING_AROUND_SELF:
			return e.global_position + Vector2.UP.rotated(TAU * float(index) / float(count)) * (e.body_size.length() * 0.8)
	return e.global_position + Vector2(e.facing * e.body_size.x * 0.5, -e.body_size.y * 0.2)

func _direction(ctx: MDSMoveContext, at: Vector2, index: int) -> Vector2:
	var e := ctx.enemy
	var to_player := ctx.player_position() - at
	match aim:
		Aim.AT_PLAYER:
			return to_player.normalized()
		Aim.AT_WHERE_PLAYER_WAS:
			return (Vector2(mem(ctx).get(&"was_at", ctx.player_position())) - at).normalized()
		Aim.FORWARD:
			return Vector2(e.facing, 0)
		Aim.DOWN:
			return Vector2.DOWN
		Aim.UP:
			return Vector2.UP
		Aim.FAN_AT_PLAYER:
			return to_player.normalized().rotated(deg_to_rad(spread) * (float(index) - float(count - 1) * 0.5))
		Aim.ALL_AROUND:
			return Vector2.RIGHT.rotated(TAU * float(index) / float(count))
	return Vector2(e.facing, 0)

## A shot (for code).
static func of(p_from: From, p_aim: Aim, p_count: int, p_speed := 420.0, p_interval := 0.15, p_damage := 1) -> MDSMoveShoot:
	var s := MDSMoveShoot.new()
	s.from = p_from
	s.aim = p_aim
	s.count = p_count
	s.speed = p_speed
	s.interval = p_interval
	s.damage = p_damage
	return s
