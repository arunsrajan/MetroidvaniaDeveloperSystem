@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/cobwebs.svg")
class_name MDSCobwebs
extends MDSEnvironmentEffect
## Cobwebs, like the Weavenest's and Shellwood's in Silksong: spider webs strung across the
## rectangle's corners (and a whole one in its middle if you like), spokes from the corner and
## sagging rings between them, some torn, dew glinting along the threads. They tremble while a
## node of [member MDSEnvironmentEffect.affect_groups] moves through them, and with
## [member stickiness] they slow it down.

@export var color := Color(0.92, 0.92, 0.96, 0.55):
	set(v):
		color = v
		_changed()
@export var dew_color := Color(1.0, 1.0, 1.0, 0.95):
	set(v):
		dew_color = v
		_changed()
@export_group("Webs")
@export var top_left := true:
	set(v):
		top_left = v
		_changed()
@export var top_right := true:
	set(v):
		top_right = v
		_changed()
@export var bottom_left := false:
	set(v):
		bottom_left = v
		_changed()
@export var bottom_right := false:
	set(v):
		bottom_right = v
		_changed()
## A whole web in the middle.
@export var middle := false:
	set(v):
		middle = v
		_changed()
## How far a corner web reaches (px).
@export_range(20.0, 1000.0) var web_radius := 150.0:
	set(v):
		web_radius = v
		_changed()
@export_range(3, 24) var spokes := 9:
	set(v):
		spokes = v
		_changed()
@export_range(1, 30) var rings := 9:
	set(v):
		rings = v
		_changed()
## How much the rings sag between spokes.
@export_range(0.0, 1.0) var sag := 0.35:
	set(v):
		sag = v
		_changed()
@export_range(0.3, 4.0) var thickness := 1.0:
	set(v):
		thickness = v
		_changed()
## Dew drops along the threads.
@export_range(0.0, 1.0) var dew := 0.5:
	set(v):
		dew = v
		_changed()
## Torn pieces of ring.
@export_range(0.0, 1.0) var torn := 0.15:
	set(v):
		torn = v
		_changed()
@export_group("Bodies")
## How hard they tremble when a body moves through them.
@export_range(0.0, 1.0) var tremble_strength := 0.8
## Share of a body's speed taken away each second it is in a web (0: none).
@export_range(0.0, 10.0) var stickiness := 0.0

## How hard they tremble now (0..1).
var tremble := 0.0
var _last: Dictionary = {} ## body -> where it was last frame

func _init() -> void:
	z_index = 3
	size = Vector2(360, 260)

func get_effect_id() -> String:
	return "cobwebs"

## Whether [param p] (in its own coordinates) is on one of its webs.
func is_in_web(p: Vector2) -> bool:
	var r := get_effect_rect()
	var q := p - r.position
	if middle and q.distance_to(r.size * 0.5) <= minf(minf(r.size.x, r.size.y) * 0.48, web_radius * 1.4):
		return true
	var on := [top_left and q.length() <= web_radius,
		top_right and q.distance_to(Vector2(r.size.x, 0.0)) <= web_radius,
		bottom_left and q.distance_to(Vector2(0.0, r.size.y)) <= web_radius,
		bottom_right and q.distance_to(r.size) <= web_radius]
	return on.has(true)

func _build() -> void:
	add_quad(shader("cobwebs"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"dew_color", dew_color)
	set_param(&"corners", (1 if top_left else 0) | (2 if top_right else 0) | (4 if bottom_left else 0) | (8 if bottom_right else 0) | (16 if middle else 0))
	set_param(&"web_radius", web_radius)
	set_param(&"spokes", spokes)
	set_param(&"rings", rings)
	set_param(&"sag", sag)
	set_param(&"thickness", thickness)
	set_param(&"dew", dew)
	set_param(&"torn", torn)

func _tick(delta: float) -> void:
	# Trembling: as hard as the fastest body moving through a web, dying down after.
	var moved := 0.0
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform2D.IDENTITY
	var seen: Dictionary = {}
	for b in bodies_inside(0.0, get_effect_rect()):
		var p := inv * b.global_position
		if is_in_web(p):
			if _last.has(b):
				moved = maxf(moved, p.distance_to(_last[b]))
			seen[b] = p
	_last = seen
	tremble = maxf(move_toward(tremble, 0.0, delta * 1.5), clampf(moved / 4.0, 0.0, 1.0) * tremble_strength)
	set_param(&"tremble", tremble)

func _affect(body: Node2D, delta: float, strength: float) -> void:
	if stickiness > 0.0 and "velocity" in body and is_in_web(global_transform.affine_inverse() * body.global_position):
		var v: Vector2 = body.get("velocity")
		body.set("velocity", v * maxf(0.0, 1.0 - stickiness * strength * delta))
