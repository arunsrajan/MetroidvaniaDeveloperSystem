@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_flyer.svg")
class_name MDSFlyer
extends MDSEnemy
## An enemy that flies: Hover (bobbing about where it started), Swoop (a dive at where the player
## was), Return (back home), Hurt, Dead. No gravity.

@export var hover_radius := 40.0
@export var hover_speed := 60.0
@export var swoop_speed := 320.0
@export var swoop_time := 1.1
@export var swoop_cooldown := 1.4

func _init() -> void:
	super()
	look = Look.BAT
	uses_gravity = false
	body_size = Vector2(36, 28)
	body_color = Color(0.45, 0.35, 0.6)

static func build() -> MDSFlyer:
	var e := MDSFlyer.new()
	e.name = "Flyer"
	e._build_missing(false)
	return e

func _make_states() -> Array[Node]:
	return MDSWalker._named([Hover.new(), Swoop.new(), Return.new()], ["Hover", "Swoop", "Return"])

class Hover extends MDSEnemyState:
	func physics_update(_delta: float) -> void:
		var f := enemy as MDSFlyer
		var t := elapsed()
		var target := f.home + Vector2(cos(t * 0.9) * f.hover_radius, sin(t * 1.7) * f.hover_radius * 0.4)
		f.velocity = (target - f.global_position).limit_length(f.hover_speed * 2.0) * 2.0
		f.move()
		if f.sees_player() and t > f.swoop_cooldown:
			go(&"Swoop")

class Swoop extends MDSEnemyState:
	var dir := Vector2.ZERO
	func enter(_previous: StringName, _data: Dictionary) -> void:
		var p := enemy.get_player()
		dir = (p.global_position - enemy.global_position).normalized() if p else Vector2(enemy.facing, 0.5).normalized()
		enemy.facing = 1 if dir.x >= 0.0 else -1
	func physics_update(_delta: float) -> void:
		var f := enemy as MDSFlyer
		f.velocity = dir * f.swoop_speed
		f.move()
		if elapsed() > f.swoop_time or f.get_slide_collision_count() > 0:
			go(&"Return")

class Return extends MDSEnemyState:
	func physics_update(_delta: float) -> void:
		var f := enemy as MDSFlyer
		var to := f.home - f.global_position
		f.velocity = to.normalized() * f.hover_speed * 2.5
		f.move()
		if to.length() < 12.0 or elapsed() > 3.0:
			go(&"Hover")
