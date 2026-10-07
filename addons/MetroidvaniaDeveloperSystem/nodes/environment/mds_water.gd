@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/water.svg")
class_name MDSWater
extends MDSEnvironmentEffect
## A pool or a flooded passage: a rolling surface with a bright line along it, what is behind
## showing through, bent and tinted deeper toward the bottom, caustic light rippling near the
## surface and bubbles rising. Put the rectangle's top edge where the surface rests. Bodies of
## [member affect_groups] going in and out are reported by
## [signal MDSEnvironmentEffect.body_entered_effect] and
## [signal MDSEnvironmentEffect.body_exited_effect] (for swimming); with [member drag] they
## are slowed in it.

@export var shallow_color := Color(0.25, 0.62, 0.72, 0.45):
	set(v):
		shallow_color = v
		_changed()
@export var deep_color := Color(0.04, 0.16, 0.30, 0.85):
	set(v):
		deep_color = v
		_changed()
@export var surface_color := Color(0.85, 0.97, 1.0, 0.9):
	set(v):
		surface_color = v
		_changed()
@export var caustic_color := Color(0.75, 0.95, 1.0):
	set(v):
		caustic_color = v
		_changed()
@export_group("Motion")
@export_range(0.0, 40.0) var wave_height := 4.0:
	set(v):
		wave_height = v
		_queue_rebuild()
@export_range(0.0, 5.0) var wave_speed := 1.0:
	set(v):
		wave_speed = v
		_changed()
@export_range(0.0, 1.0) var refraction := 0.5:
	set(v):
		refraction = v
		_changed()
@export_range(0.0, 1.0) var caustics := 0.6:
	set(v):
		caustics = v
		_changed()
@export_range(0.0, 1.0) var bubbles := 0.3:
	set(v):
		bubbles = v
		_changed()
@export_group("Force")
## Share of a body's speed taken away each second it is in the water (0: none).
@export_range(0.0, 10.0) var drag := 0.0

func _init() -> void:
	z_index = 3
	size = Vector2(480, 200)

func get_effect_id() -> String:
	return "water"

func _build() -> void:
	var above := wave_height * 2.0 + 2.0
	add_quad(shader("water"), Rect2(Vector2(0.0, -above), size + Vector2(0.0, above))).set_shader_parameter("surface_y", above)

func _update_params() -> void:
	set_param(&"shallow_color", shallow_color)
	set_param(&"deep_color", deep_color)
	set_param(&"surface_color", surface_color)
	set_param(&"caustic_color", caustic_color)
	set_param(&"wave_height", wave_height)
	set_param(&"wave_speed", wave_speed)
	set_param(&"refraction", refraction)
	set_param(&"caustics", caustics)
	set_param(&"bubbles", bubbles)

func _affect(body: Node2D, delta: float, strength: float) -> void:
	if drag > 0.0 and "velocity" in body:
		var v: Vector2 = body.get("velocity")
		body.set("velocity", v * maxf(0.0, 1.0 - drag * strength * delta))
