@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_hurtbox.svg")
class_name MDSHurtbox
extends Area2D
## Where something can be hit: an Area2D with a collision shape, on the
## [code]player_hurtbox[/code] layer (team PLAYER) or the [code]enemy_hurtbox[/code] layer (ENEMY,
## NEUTRAL: enemies, breakables, switches). [MDSHitbox]es of the other teams find it and give it
## their hit ([method receive]): its [member health] takes it, times [member damage_multiplier]
## (a weak spot, an armoured back). A body with [code]mds_take_hit(info) -> int[/code] (a
## breakable, a switch) takes the hit itself instead.

signal hurt(info: MDSDamageInfo)

enum Team { PLAYER, ENEMY, HAZARD, NEUTRAL }

## The health hits go to. Empty: the body's [MDSHealth].
@export var health: MDSHealth
@export var team: Team = Team.ENEMY
@export var damage_multiplier := 1.0
@export var enabled := true
## Asked before a hit lands: returns true to block it (a parry). Set by code.
var blocker: Callable

func _ready() -> void:
	collision_layer = MDSGameplaySetup.bit("player_hurtbox") if team == Team.PLAYER else MDSGameplaySetup.bit("enemy_hurtbox")
	collision_mask = 0
	monitoring = false
	monitorable = true

## A hurtbox for [param p_team] of [param size], centred on its body.
static func make(p_team: Team, size: Vector2) -> MDSHurtbox:
	var h := MDSHurtbox.new()
	h.team = p_team
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	h.add_child(cs)
	return h

## The body it belongs to (its parent).
func get_body() -> Node:
	return get_parent()

func get_health() -> MDSHealth:
	if is_instance_valid(health):
		return health
	health = MDSHealth.of(get_body())
	return health

## Takes the hit [param info]. Returns the damage done (0: it didn't land; a body taking hits
## itself returns what it says).
func receive(info: MDSDamageInfo) -> int:
	if not enabled:
		return 0
	if blocker.is_valid() and blocker.call(info):
		return 0
	var body := get_body()
	var dmg := 0
	if body and body.has_method(&"mds_take_hit"):
		dmg = int(body.call(&"mds_take_hit", info))
	else:
		var h := get_health()
		dmg = h.apply_damage(info, damage_multiplier) if h else 0
	if dmg > 0:
		hurt.emit(info)
	return dmg
