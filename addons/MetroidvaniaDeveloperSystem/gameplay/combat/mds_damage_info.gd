@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_damage_info.svg")
class_name MDSDamageInfo
extends RefCounted
## One hit: how much, of what type, the push it gives, how long the game freezes when it lands,
## what dealt it, and which breakable kinds it breaks. [MDSHitbox] makes one per target hit;
## [MDSHealth] takes it.

## Damage before resistances and defense.
var amount := 1
## physical, fire, ice, shock, void, environment (or any name resistances use).
var damage_type := "physical"
## Push: x away from the source, y up (negative).
var knockback := Vector2.ZERO
var hitstop_ms := 0
## What dealt it (the attacker, a hazard, an environment effect).
var source: Node
var attack_id := ""
## [MDSBreakable] kinds it breaks.
var breaks: PackedStringArray = []
## Lands even during invulnerability frames (a pit, a crushing wall).
var ignores_iframes := false
## Hazard hits that send the player back to safe ground ([MDSHazard] RESPAWN, lava).
var respawn := false
## Where it came from (global), for the knockback's direction.
var origin := Vector2.INF

static func make(p_amount: int, p_type := "physical", p_source: Node = null) -> MDSDamageInfo:
	var d := MDSDamageInfo.new()
	d.amount = p_amount
	d.damage_type = p_type
	d.source = p_source
	if p_source is Node2D and (p_source as Node2D).is_inside_tree():
		d.origin = (p_source as Node2D).global_position
	return d

## A copy (each target gets its own).
func copy() -> MDSDamageInfo:
	var d := MDSDamageInfo.new()
	d.amount = amount
	d.damage_type = damage_type
	d.knockback = knockback
	d.hitstop_ms = hitstop_ms
	d.source = source
	d.attack_id = attack_id
	d.breaks = breaks.duplicate()
	d.ignores_iframes = ignores_iframes
	d.respawn = respawn
	d.origin = origin
	return d
