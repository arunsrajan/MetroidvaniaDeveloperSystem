@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_walker.svg")
class_name MDSWalker
extends MDSEnemy
## An enemy that walks: Patrol (to and fro, turning at walls and ledges), Turn, Chase (toward the
## player it sees, stopping at ledges), Attack (a lunge when close), Hurt, Dead.

@export var patrol_speed := 70.0
@export var chase_speed := 150.0
@export var attack_range := 70.0
@export var lunge_speed := 300.0
@export var windup_time := 0.3

func _init() -> void:
	super()
	look = Look.CRAWLER

static func build() -> MDSWalker:
	var e := MDSWalker.new()
	e.name = "Walker"
	e._build_missing(false)
	return e

func _make_states() -> Array[Node]:
	return _named([Patrol.new(), Turn.new(), Chase.new(), Attack.new()], ["Patrol", "Turn", "Chase", "Attack"])

static func _named(states: Array, names: Array) -> Array[Node]:
	var out: Array[Node] = []
	for i in states.size():
		states[i].name = names[i]
		out.append(states[i])
	return out

class Patrol extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		var w := enemy as MDSWalker
		w.fall(delta)
		w.walk(w.patrol_speed, delta)
		w.move()
		if w.sees_player():
			go(&"Chase")
		elif w.at_wall() or w.at_ledge():
			go(&"Turn")

class Turn extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		enemy.fall(delta)
		enemy.halt(delta)
		enemy.move()
		if elapsed() >= 0.3:
			enemy.turn()
			go(&"Patrol")

class Chase extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		var w := enemy as MDSWalker
		w.face_player()
		w.fall(delta)
		if w.at_ledge() or w.at_wall():
			w.halt(delta)
		else:
			w.walk(w.chase_speed, delta)
		w.move()
		if not w.sees_player() and elapsed() > 1.0:
			go(&"Patrol")
		elif w.distance_to_player() < w.attack_range:
			go(&"Attack")

class Attack extends MDSEnemyState:
	func physics_update(delta: float) -> void:
		var w := enemy as MDSWalker
		w.fall(delta)
		if elapsed() < w.windup_time:
			w.halt(delta)
		elif elapsed() < w.windup_time + 0.25:
			if w.at_ledge():
				w.halt(delta)
			else:
				w.velocity.x = w.facing * w.lunge_speed
		else:
			go(&"Chase")
		w.move()
