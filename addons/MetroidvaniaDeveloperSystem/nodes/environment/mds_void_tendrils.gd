@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/void_tendrils.svg")
class_name MDSVoidTendrils
extends MDSEnvironmentEffect
## Void tendrils, like the Abyss's in Silksong and Hollow Knight: tendrils of black void rising
## from the rectangle's bottom edge (put it on the floor) out of a pool of darkness, writhing, a
## dark violet glow at their rims and motes of void drifting up. They lean toward the nodes of
## [member MDSEnvironmentEffect.affect_groups] that come within [member reach] px. With
## [member damage], a body touching them is hurt every [member damage_interval] seconds.

@export var color := Color(0.02, 0.01, 0.04):
	set(v):
		color = v
		_changed()
## Their rims and the motes.
@export var glow_color := Color(0.5, 0.25, 1.0):
	set(v):
		glow_color = v
		_changed()
@export_range(0.0, 1.0) var density := 0.75:
	set(v):
		density = v
		_changed()
## Distance between tendrils (px).
@export_range(10.0, 300.0) var spacing := 46.0:
	set(v):
		spacing = v
		_changed()
## How tall the tallest rise (px).
@export_range(10.0, 1200.0) var height := 160.0:
	set(v):
		height = v
		_changed()
## How much their heights vary.
@export_range(0.0, 1.0) var variation := 0.5:
	set(v):
		variation = v
		_changed()
@export_range(2.0, 80.0) var thickness := 14.0:
	set(v):
		thickness = v
		_changed()
@export_group("Motion")
@export_range(0.0, 3.0) var writhe := 1.0:
	set(v):
		writhe = v
		_changed()
@export_range(0.0, 5.0) var speed := 1.0:
	set(v):
		speed = v
		_changed()
## How close (px) a body must come for them to reach for it (0: they don't).
@export_range(0.0, 800.0) var reach := 160.0:
	set(v):
		reach = v
		_changed()
@export_group("Look")
## The pool of darkness at their roots.
@export_range(0.0, 1.0) var pool := 0.7:
	set(v):
		pool = v
		_changed()
@export_range(0.0, 1.0) var motes := 0.4:
	set(v):
		motes = v
		_changed()
@export_group("Harm")
## Damage per hit to a body among them. 0: none (scenery).
@export var damage := 0.0
@export_range(0.05, 10.0, 0.05) var damage_interval := 0.8

func _init() -> void:
	z_index = 20
	size = Vector2(480, 220)

func get_effect_id() -> String:
	return "void_tendrils"

## Where they hurt: from the floor up to the tallest tendril.
func get_body_rect() -> Rect2:
	var r := get_effect_rect()
	var h := minf(height, r.size.y)
	return Rect2(Vector2(r.position.x, r.end.y - h), Vector2(r.size.x, h))

func _build() -> void:
	add_quad(shader("void_tendrils"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"glow_color", glow_color)
	set_param(&"density", density)
	set_param(&"spacing", spacing)
	set_param(&"height", height)
	set_param(&"variation", variation)
	set_param(&"thickness", thickness)
	set_param(&"writhe", writhe)
	set_param(&"speed", speed)
	set_param(&"reach", reach)
	set_param(&"pool", pool)
	set_param(&"motes", motes)

func _tick(_delta: float) -> void:
	if reach > 0.0:
		send_bodies(reach)
	else:
		set_param(&"body_count", 0)

func _affect(body: Node2D, _delta: float, strength: float) -> void:
	if damage > 0.0:
		hurt_body(body, damage * strength, damage_interval)
