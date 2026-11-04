@tool
class_name MDSMoveZones
extends MDSMove
## Places in the arena that warn, then hurt ([MDSCombatZone]): fireworks, columns rising from the
## floor, a slash at the player's spot, a trail left behind it. With [member hits_to_break] they stay
## as walls for the player to cut down.

enum Place { RANDOM_IN_ARENA, AT_PLAYER, AROUND_PLAYER, FLOOR_RANDOM, FLOOR_EVEN, CEILING_RANDOM, CEILING_EVEN, AT_SELF }

@export var place: Place = Place.RANDOM_IN_ARENA
@export_range(1, 32, 1, "or_greater") var count := 3
## Seconds between one zone and the next.
@export_range(0.0, 5.0, 0.01, "or_greater") var interval := 0.15
@export var shape: MDSCombatZone.Shape = MDSCombatZone.Shape.CIRCLE
## CIRCLE: x is the diameter. BOX: x wide, y tall, grown from the floor or the ceiling it stands on.
@export var size := Vector2(120, 120)
## A BOX on the floor or the ceiling reaches the other side, however far that is (a wall).
@export var span_room := false
## Seconds of warning.
@export_range(0.0, 10.0, 0.01, "or_greater") var telegraph := 0.7
## Seconds it hurts.
@export_range(0.01, 60.0, 0.01, "or_greater") var active := 0.25
## Hits it takes to break (0: it can't be hit, and goes when its time is up).
@export var hits_to_break := 0
## It goes when the enemy is staggered or dies.
@export var clear_on_stagger := true
@export var color := Color(1.0, 0.75, 0.35)
## It ends only when the last zone is gone. Off: when the last one is placed.
@export var wait_until_gone := false
## Shakes the camera when each goes off (pixels).
@export var shake := 0.0

func _start(ctx: MDSMoveContext) -> void:
	var m := mem(ctx)
	m[&"placed"] = 0
	m[&"next"] = 0.0
	m[&"zones"] = []

func _update(ctx: MDSMoveContext, _delta: float) -> Status:
	var m := mem(ctx)
	var t := elapsed(ctx)
	while int(m[&"placed"]) < count and t >= float(m[&"next"]):
		_place(ctx, int(m[&"placed"]))
		m[&"placed"] = int(m[&"placed"]) + 1
		m[&"next"] = float(m[&"next"]) + interval
	if int(m[&"placed"]) < count:
		return Status.RUNNING
	if wait_until_gone:
		for z: Variant in m[&"zones"]:
			if is_instance_valid(z):
				return Status.RUNNING
	return Status.DONE

func _place(ctx: MDSMoveContext, index: int) -> void:
	var at := _where(ctx, index)
	var z := MDSCombatZone.new()
	z.shape = shape
	z.size = size
	z.telegraph = telegraph / ctx.speed()
	z.active_time = active
	z.color = color
	z.attack = get_attack(ctx)
	z.source = ctx.enemy
	z.hits_to_break = hits_to_break
	z.clear_on_stagger = clear_on_stagger
	z.shake = shake
	z.anchor_top = place in [Place.CEILING_RANDOM, Place.CEILING_EVEN]
	z.anchor_bottom = place in [Place.FLOOR_RANDOM, Place.FLOOR_EVEN]
	if span_room and shape == MDSCombatZone.Shape.BOX:
		if z.anchor_top:
			z.size.y = ctx.floor_at(at + Vector2(0, 2)).y - at.y
		elif z.anchor_bottom:
			z.size.y = at.y - ctx.ceiling_at(at - Vector2(0, 2)).y
	ctx.spawn_parent().add_child(z)
	z.global_position = at
	ctx.track(z)
	mem(ctx)[&"zones"].append(z)

func _where(ctx: MDSMoveContext, index: int) -> Vector2:
	var r := ctx.arena_rect()
	var margin := minf(size.x * 0.5, r.size.x * 0.25)
	var random_x := ctx.rng.randf_range(r.position.x + margin, r.end.x - margin)
	var even_x := r.position.x + r.size.x * (float(index) + 0.5) / float(count)
	var in_arena := r.get_center().y
	match place:
		Place.RANDOM_IN_ARENA:
			return Vector2(random_x, ctx.rng.randf_range(r.position.y + margin, r.end.y - margin))
		Place.AT_PLAYER:
			return ctx.player_position()
		Place.AROUND_PLAYER:
			return ctx.player_position() + Vector2.RIGHT.rotated(TAU * float(index) / float(count)) * size.x
		Place.FLOOR_RANDOM:
			return ctx.floor_at(Vector2(random_x, in_arena))
		Place.FLOOR_EVEN:
			return ctx.floor_at(Vector2(even_x, in_arena))
		Place.CEILING_RANDOM:
			return ctx.ceiling_at(Vector2(random_x, in_arena))
		Place.CEILING_EVEN:
			return ctx.ceiling_at(Vector2(even_x, in_arena))
	return ctx.enemy.global_position

## Zones (for code).
static func of(p_place: Place, p_count: int, p_size: Vector2, p_telegraph := 0.7, p_active := 0.25, p_shape := MDSCombatZone.Shape.CIRCLE, p_damage := 1) -> MDSMoveZones:
	var z := MDSMoveZones.new()
	z.place = p_place
	z.count = p_count
	z.size = p_size
	z.telegraph = p_telegraph
	z.active = p_active
	z.shape = p_shape
	z.damage = p_damage
	return z
