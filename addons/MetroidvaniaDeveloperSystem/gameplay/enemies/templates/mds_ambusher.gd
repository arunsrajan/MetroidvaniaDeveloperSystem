@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_ambusher.svg")
class_name MDSAmbusher
extends MDSEnemy
## An enemy that lies in wait: Hidden (in the ground, harmless and unhittable), Reveal (it bursts
## out when the player comes within [member reveal_range]), Attack (a lunge at the player), Retreat
## (back into the ground when the player is far), Dead.

@export var reveal_range := 150.0
@export var lunge_speed := 320.0
@export var hide_after := 2.5

func _init() -> void:
	super()
	look = Look.WORM
	body_size = Vector2(36, 48)
	body_color = Color(0.55, 0.4, 0.5)

static func build() -> MDSAmbusher:
	var e := MDSAmbusher.new()
	e.name = "Ambusher"
	e._build_missing(false)
	return e

func _make_states() -> Array[Node]:
	return MDSWalker._named([Hidden.new(), Reveal.new(), Attack.new(), Retreat.new()], ["Hidden", "Reveal", "Attack", "Retreat"])

## Hidden or not: invisible, not hittable, harmless.
func set_hidden(on: bool) -> void:
	modulate.a = 0.15 if on else 1.0
	hurtbox.enabled = not on
	contact.active = not on

class Hidden extends MDSEnemyState:
	func enter(_previous: StringName, _data: Dictionary) -> void:
		(enemy as MDSAmbusher).set_hidden(true)
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()
		if enemy.distance_to_player() < (enemy as MDSAmbusher).reveal_range:
			go(&"Reveal")
	func exit(_next: StringName) -> void:
		(enemy as MDSAmbusher).set_hidden(false)

class Reveal extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.face_player()
		enemy.fall(delta)
		enemy.move()
		if elapsed() >= 0.35:
			go(&"Attack")

class Attack extends MDSEnemyState:
	func enter(_previous: StringName, _data: Dictionary) -> void:
		enemy.face_player()
		enemy.velocity = Vector2(enemy.facing * (enemy as MDSAmbusher).lunge_speed, -260.0)
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.move()
		if elapsed() > 0.2 and enemy.is_on_floor():
			enemy.halt(delta)
			if elapsed() > (enemy as MDSAmbusher).hide_after * 0.5:
				go(&"Retreat" if enemy.distance_to_player() > (enemy as MDSAmbusher).reveal_range * 1.6 else &"Attack")

class Retreat extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()
		enemy.modulate.a = maxf(0.15, 1.0 - elapsed() * 2.0)
		if elapsed() > 0.45:
			go(&"Hidden")
