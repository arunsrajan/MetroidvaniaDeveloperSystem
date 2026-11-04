@tool
class_name MDSMoveCondition
extends Resource
## A question about the fight, for [member MDSMove.when] and [member MDSMove.cancel_when]. Extend it
## and override [method _test] for your own.

enum Kind { ALWAYS, PLAYER_NEAR, PLAYER_FAR, PLAYER_ABOVE, PLAYER_BELOW, PLAYER_BEHIND, PLAYER_IN_AIR, PLAYER_ON_WALL, PLAYER_OUTSIDE_ARENA, HEALTH_BELOW, PHASE_AT_LEAST, HIT_WITHIN, FLAG, SUMMONS_BELOW, ON_FLOOR, AT_WALL, CHANCE }

@export var kind: Kind = Kind.ALWAYS
## Pixels (NEAR, FAR, ABOVE, BELOW), a share of its health from 0 to 1 (HEALTH_BELOW), a phase
## (PHASE_AT_LEAST), seconds (HIT_WITHIN), a count (SUMMONS_BELOW), a chance from 0 to 1 (CHANCE).
@export var value := 0.0
## The flag's name (FLAG; see [MDSMoveCue]).
@export var flag := &""
## Asks the opposite.
@export var invert := false

func holds(ctx: MDSMoveContext) -> bool:
	return _test(ctx) != invert

func _test(ctx: MDSMoveContext) -> bool:
	var e := ctx.enemy
	var p := e.get_player()
	match kind:
		Kind.ALWAYS:
			return true
		Kind.PLAYER_NEAR:
			return p != null and e.distance_to_player() <= value
		Kind.PLAYER_FAR:
			return p != null and e.distance_to_player() >= value
		Kind.PLAYER_ABOVE:
			return p != null and p.global_position.y < e.global_position.y - value
		Kind.PLAYER_BELOW:
			return p != null and p.global_position.y > e.global_position.y + value
		Kind.PLAYER_BEHIND:
			return p != null and e.player_side() != e.facing
		Kind.PLAYER_IN_AIR:
			return p is CharacterBody2D and not (p as CharacterBody2D).is_on_floor()
		Kind.PLAYER_ON_WALL:
			return p is CharacterBody2D and (p as CharacterBody2D).is_on_wall_only()
		Kind.PLAYER_OUTSIDE_ARENA:
			return p != null and not ctx.arena_rect().has_point(p.global_position)
		Kind.HEALTH_BELOW:
			return e.health != null and float(e.health.current) / float(maxi(1, e.health.get_max())) <= value
		Kind.PHASE_AT_LEAST:
			return ctx.phase() >= int(value)
		Kind.HIT_WITHIN:
			return ctx.since_hit() <= value
		Kind.FLAG:
			return ctx.flags.get(flag, false)
		Kind.SUMMONS_BELOW:
			return ctx.summons_alive() < int(value)
		Kind.ON_FLOOR:
			return e.is_on_floor()
		Kind.AT_WALL:
			return e.at_wall()
		Kind.CHANCE:
			return ctx.rng.randf() < value
	return false

## A condition (for code).
static func make(p_kind: Kind, p_value := 0.0, p_invert := false, p_flag := &"") -> MDSMoveCondition:
	var c := MDSMoveCondition.new()
	c.kind = p_kind
	c.value = p_value
	c.invert = p_invert
	c.flag = p_flag
	return c
