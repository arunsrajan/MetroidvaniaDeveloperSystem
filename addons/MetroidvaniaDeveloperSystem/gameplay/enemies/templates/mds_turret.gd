@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_turret.svg")
class_name MDSTurret
extends MDSEnemy
## An enemy fixed in place that shoots: Idle (until it sees the player), Aim (turning toward it for
## [member aim_time]), Fire (an [MDSProjectile] at it, then [member fire_interval] before the
## next), Hurt, Dead. No gravity, no knockback.

## The shot ([MDSProjectile] scene). Empty: a plain bolt.
@export var projectile: PackedScene
@export var projectile_speed := 380.0
@export var projectile_damage := 1
@export var aim_time := 0.45
@export var fire_interval := 1.6

var aim := Vector2.LEFT

func _init() -> void:
	super()
	look = Look.TURRET
	uses_gravity = false
	body_color = Color(0.5, 0.52, 0.58)

static func build() -> MDSTurret:
	var e := MDSTurret.new()
	e.name = "Turret"
	e._build_missing(false)
	return e

func _ready() -> void:
	super()
	if knockback:
		knockback.resistance = 1.0

func _make_states() -> Array[Node]:
	return MDSWalker._named([TurretIdle.new(), Aim.new(), Fire.new()], ["Idle", "Aim", "Fire"])

## Fires one shot along [member aim]. Returns it.
func fire() -> MDSProjectile:
	var a := MDSAttackData.make("bolt", projectile_damage, [])
	a = style_attack(a)
	a.knockback = Vector2(200, -150)
	var parent: Node = get_parent() if get_parent() else self
	var p := MDSProjectile.fire(projectile, parent, global_position + aim * (body_size.x * 0.6), aim, MDSHitbox.Team.ENEMY, a, self)
	if p:
		p.velocity = aim * projectile_speed
		p.color = Color(1.0, 0.55, 0.4)
	return p

class TurretIdle extends MDSEnemyState:
	func physics_update(_delta: float) -> void:
		enemy.velocity = Vector2.ZERO
		if enemy.sees_player():
			go(&"Aim")

class Aim extends MDSEnemyState:
	func physics_update(_delta: float) -> void:
		var t := enemy as MDSTurret
		var p := t.get_player()
		if p:
			t.aim = (p.global_position - t.global_position).normalized()
			t.facing = 1 if t.aim.x >= 0.0 else -1
		if not t.sees_player():
			go(&"Idle")
		elif elapsed() >= t.aim_time:
			go(&"Fire")

class Fire extends MDSEnemyState:
	func enter(_previous: StringName, _data: Dictionary) -> void:
		(enemy as MDSTurret).fire()
	func physics_update(_delta: float) -> void:
		if elapsed() >= (enemy as MDSTurret).fire_interval:
			go(&"Aim" if enemy.sees_player() else &"Idle")
