@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/hanging_moss.svg")
class_name MDSHangingMoss
extends MDSEnvironmentEffect
## Hanging moss and vines, like Greymoor's and the Moss Grotto's in Silksong: leafy strands
## hanging from the rectangle's top edge (put it under a ceiling), swaying in a draught, a darker
## layer behind. They part around the nodes of [member MDSEnvironmentEffect.affect_groups] that
## pass through them (the player), and fall back into place behind.

@export var color := Color(0.17, 0.27, 0.13):
	set(v):
		color = v
		_changed()
## Toward the tips.
@export var tip_color := Color(0.45, 0.6, 0.27):
	set(v):
		tip_color = v
		_changed()
## The layer behind.
@export var shadow_color := Color(0.06, 0.09, 0.06):
	set(v):
		shadow_color = v
		_changed()
@export_range(0.0, 1.0) var density := 0.7:
	set(v):
		density = v
		_changed()
## Distance between strands (px).
@export_range(3.0, 60.0) var strand_spacing := 9.0:
	set(v):
		strand_spacing = v
		_changed()
## How far the longest hang (px).
@export_range(10.0, 1000.0) var strand_length := 140.0:
	set(v):
		strand_length = v
		_changed()
## How much their lengths vary.
@export_range(0.0, 1.0) var variation := 0.6:
	set(v):
		variation = v
		_changed()
@export_range(1.0, 20.0) var thickness := 5.0:
	set(v):
		thickness = v
		_changed()
## Leafy bumps along them.
@export_range(0.0, 1.0) var leaves := 0.6:
	set(v):
		leaves = v
		_changed()
@export_group("Motion")
@export_range(0.0, 3.0) var sway := 1.0:
	set(v):
		sway = v
		_changed()
@export_range(0.0, 5.0) var speed := 1.0:
	set(v):
		speed = v
		_changed()
## How far around a body strands are pushed aside (px; 0: they don't part).
@export_range(0.0, 200.0) var part_radius := 40.0:
	set(v):
		part_radius = v
		_changed()

func _init() -> void:
	z_index = 22
	size = Vector2(480, 200)

func get_effect_id() -> String:
	return "hanging_moss"

func _build() -> void:
	add_quad(shader("hanging_moss"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"tip_color", tip_color)
	set_param(&"shadow_color", shadow_color)
	set_param(&"density", density)
	set_param(&"strand_spacing", strand_spacing)
	set_param(&"strand_length", strand_length)
	set_param(&"variation", variation)
	set_param(&"thickness", thickness)
	set_param(&"leaves", leaves)
	set_param(&"sway", sway)
	set_param(&"speed", speed)
	set_param(&"part_radius", part_radius)

func _tick(_delta: float) -> void:
	if part_radius > 0.0:
		send_bodies(part_radius)
	else:
		set_param(&"body_count", 0)
