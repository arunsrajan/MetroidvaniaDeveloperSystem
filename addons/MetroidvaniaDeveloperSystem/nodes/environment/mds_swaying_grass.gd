@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/swaying_grass.svg")
class_name MDSSwayingGrass
extends MDSEnvironmentEffect
## Swaying grass, like the meadows of Silksong's Far Fields and Hollow Knight's Greenpath: blades
## along the rectangle's bottom edge (put it on the floor) swaying in gusts of wind, a flower on
## some. They bend away from the nodes of [member MDSEnvironmentEffect.affect_groups] walking
## through them (the player) and spring back behind.

@export var color := Color(0.12, 0.29, 0.14):
	set(v):
		color = v
		_changed()
## Toward the tips.
@export var tip_color := Color(0.46, 0.7, 0.3):
	set(v):
		tip_color = v
		_changed()
@export var flower_color := Color(0.96, 0.86, 0.55):
	set(v):
		flower_color = v
		_changed()
@export_range(0.0, 1.0) var density := 0.85:
	set(v):
		density = v
		_changed()
## Distance between blades (px).
@export_range(1.5, 40.0) var blade_spacing := 5.0:
	set(v):
		blade_spacing = v
		_changed()
@export_range(4.0, 300.0) var blade_height := 34.0:
	set(v):
		blade_height = v
		_changed()
## How much their heights vary.
@export_range(0.0, 1.0) var variation := 0.5:
	set(v):
		variation = v
		_changed()
@export_range(1.0, 16.0) var blade_width := 3.0:
	set(v):
		blade_width = v
		_changed()
## A share of the blades with a flower.
@export_range(0.0, 1.0) var flowers := 0.08:
	set(v):
		flowers = v
		_changed()
@export_group("Motion")
@export_range(0.0, 3.0) var sway := 1.0:
	set(v):
		sway = v
		_changed()
## Which way the wind leans them (-1 left, 1 right).
@export_range(-1.0, 1.0) var wind := 0.15:
	set(v):
		wind = v
		_changed()
@export_range(0.0, 5.0) var speed := 1.0:
	set(v):
		speed = v
		_changed()
## How far around a body blades bend away (px).
@export_range(0.0, 200.0) var part_radius := 36.0:
	set(v):
		part_radius = v
		_changed()
## How far they bend (0: bodies don't bend them).
@export_range(0.0, 2.0) var bend := 1.0:
	set(v):
		bend = v
		_changed()

func _init() -> void:
	z_index = 22
	size = Vector2(480, 60)

func get_effect_id() -> String:
	return "swaying_grass"

func _build() -> void:
	add_quad(shader("swaying_grass"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"tip_color", tip_color)
	set_param(&"flower_color", flower_color)
	set_param(&"density", density)
	set_param(&"blade_spacing", blade_spacing)
	set_param(&"blade_height", blade_height)
	set_param(&"variation", variation)
	set_param(&"blade_width", blade_width)
	set_param(&"flowers", flowers)
	set_param(&"sway", sway)
	set_param(&"wind", wind)
	set_param(&"speed", speed)
	set_param(&"part_radius", part_radius)
	set_param(&"bend", bend)

func _tick(_delta: float) -> void:
	if bend > 0.0:
		send_bodies(part_radius + blade_height)
	else:
		set_param(&"body_count", 0)
