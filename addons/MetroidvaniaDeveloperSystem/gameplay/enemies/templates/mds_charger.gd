@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_charger.svg")
class_name MDSCharger
extends MDSEnemy
## An enemy that charges: Idle (until it sees the player), Windup (it shakes, telegraphing, for
## [member windup_time]), Charge (straight ahead at [member charge_speed]), Stunned (it hit a wall:
## dazed and open to hits for [member stun_time]), Hurt, Dead.

@export var windup_time := 0.6
@export var charge_speed := 440.0
@export var max_charge_time := 1.8
@export var stun_time := 1.4

func _init() -> void:
	super()
	look = Look.BEETLE
	body_size = Vector2(52, 40)
	body_color = Color(0.6, 0.45, 0.25)

static func build() -> MDSCharger:
	var e := MDSCharger.new()
	e.name = "Charger"
	e._build_missing(false)
	return e

func _make_states() -> Array[Node]:
	return MDSWalker._named([ChargerIdle.new(), Windup.new(), Charge.new(), Stunned.new()], ["Idle", "Windup", "Charge", "Stunned"])

class ChargerIdle extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()
		if enemy.sees_player() and elapsed() > 0.4:
			enemy.face_player()
			go(&"Windup")

class Windup extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()
		enemy.position.x += sin(elapsed() * 60.0) * 0.8
		if elapsed() >= (enemy as MDSCharger).windup_time:
			go(&"Charge")

class Charge extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		var c := enemy as MDSCharger
		c.fall(delta)
		c.velocity.x = c.facing * c.charge_speed
		c.move()
		if c.at_wall():
			c.stunned_left = c.stun_time
			go(&"Stunned")
		elif elapsed() >= c.max_charge_time or c.at_ledge():
			go(&"Idle")

class Stunned extends MDSEnemyState:
	func enter(_previous: StringName, _data: Dictionary) -> void:
		enemy.velocity.x = -enemy.facing * 80.0
		enemy.stunned_left = maxf(enemy.stunned_left, (enemy as MDSCharger).stun_time)
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta, 400.0)
		enemy.move()
		if enemy.stunned_left <= 0.0:
			enemy.turn()
			go(&"Idle")
