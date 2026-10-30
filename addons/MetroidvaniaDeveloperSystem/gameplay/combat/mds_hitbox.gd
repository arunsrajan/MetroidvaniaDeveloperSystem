@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_hitbox.svg")
class_name MDSHitbox
extends Area2D
## What hits: an Area2D with a collision shape that, while [member active], hits the
## [MDSHurtbox]es of the other team it overlaps with its [member attack]. A PLAYER hitbox (an
## attack) is on the [code]player_hitbox[/code] layer and finds [code]enemy_hurtbox[/code]es; an
## ENEMY or HAZARD one (a claw, an enemy's touch, spikes) is on [code]enemy_hitbox[/code] and finds
## the [code]player_hurtbox[/code]. A team never hurts itself. With
## [member one_hit_per_target] each target is hit once until [method reset_hits] (a new swing);
## without it (an enemy's touch), a target is hit again as soon as its invulnerability ends.

signal hit_landed(target: Node, info: MDSDamageInfo)

enum Team { PLAYER, ENEMY, HAZARD }

## Every hitbox is in this group (the F1 debug overlay draws them).
const GROUP := &"mds_hitbox"

@export var attack: MDSAttackData
@export var team: Team = Team.ENEMY
@export var one_hit_per_target := true
@export var active := true
## Who attacks (the knockback pushes away from it). Empty: the parent.
@export var source: Node
## Extra damage added to the attack's (equipment, levels).
var damage_bonus := 0
## Breakable kinds added to the attack's (super attack, ground pound).
var extra_breaks: PackedStringArray = []
## Its hits send the player back to safe ground ([MDSHazard] RESPAWN).
var respawn := false

var _hit: Dictionary = {}

func _init() -> void:
	add_to_group(GROUP)

func _ready() -> void:
	collision_layer = MDSGameplaySetup.bit("player_hitbox") if team == Team.PLAYER else MDSGameplaySetup.bit("enemy_hitbox")
	collision_mask = MDSGameplaySetup.bit("enemy_hurtbox") if team == Team.PLAYER else MDSGameplaySetup.bit("player_hurtbox")
	monitoring = true
	monitorable = false
	if not attack:
		attack = MDSAttackData.make("touch")

## A hitbox of [param p_team] of [param size] with [param p_attack].
static func make(p_team: Team, size: Vector2, p_attack: MDSAttackData = null) -> MDSHitbox:
	var h := MDSHitbox.new()
	h.team = p_team
	h.attack = p_attack
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	h.add_child(cs)
	return h

## The hitbox's rectangle shape (made when it has none).
func get_rect_shape() -> RectangleShape2D:
	for c in get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			return (c as CollisionShape2D).shape
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var r := RectangleShape2D.new()
	cs.shape = r
	add_child(cs)
	return r

func get_source() -> Node:
	return source if is_instance_valid(source) else get_parent()

## Every target can be hit again (a new swing).
func reset_hits() -> void:
	_hit.clear()

## Whether a hurtbox of [param other] is one this team hits.
func hits_team(other: int) -> bool:
	match team:
		Team.PLAYER:
			return other == MDSHurtbox.Team.ENEMY or other == MDSHurtbox.Team.NEUTRAL
		_:
			return other == MDSHurtbox.Team.PLAYER
	return false

func _physics_process(_delta: float) -> void:
	if not active or not monitoring:
		return
	for a in get_overlapping_areas():
		try_hit(a)

## Hits [param area] if it is a hurtbox of the other team not hit yet. Returns the damage done.
func try_hit(area: Area2D) -> int:
	if not area is MDSHurtbox:
		return 0
	var hb := area as MDSHurtbox
	if not hits_team(hb.team) or hb.get_body() == get_source():
		return 0
	var key := hb.get_instance_id()
	if one_hit_per_target and _hit.has(key):
		return 0
	var info := make_info(hb)
	var dmg := hb.receive(info)
	if dmg > 0:
		_hit[key] = true
		MDSAttackFX.on_hit(self, hb.get_body(), info, hb)
		hit_landed.emit(hb.get_body(), info)
	return dmg

## The hit [param target] gets: the attack's damage (with the bonus), type, knockback pushing away
## from the source, hit-stop and what it breaks.
func make_info(target: Node2D) -> MDSDamageInfo:
	var a := attack if attack else MDSAttackData.make("touch")
	var src := get_source()
	var info := MDSDamageInfo.make(a.damage + damage_bonus, a.damage_type, src)
	var from: Vector2 = (src as Node2D).global_position if src is Node2D else global_position
	info.origin = from
	var dir := signf(target.global_position.x - from.x)
	if dir == 0.0:
		dir = 1.0
	info.knockback = Vector2(a.knockback.x * dir, a.knockback.y)
	info.hitstop_ms = a.hitstop_ms
	info.attack_id = a.id
	info.breaks = a.breaks.duplicate()
	info.breaks.append_array(extra_breaks)
	info.respawn = respawn
	return info
