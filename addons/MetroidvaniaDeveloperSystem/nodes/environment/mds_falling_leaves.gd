@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/leaves.svg")
class_name MDSFallingLeaves
extends MDSEnvironmentEffect
## Leaves or petals drifting down: each tumbles as it falls, showing its paler back, swaying
## on the breeze. Each leaf takes one of three colors. A far plane falls behind the terrain.

@export var color_a := Color(0.85, 0.45, 0.14):
	set(v):
		color_a = v
		_changed()
@export var color_b := Color(0.72, 0.20, 0.10):
	set(v):
		color_b = v
		_changed()
@export var color_c := Color(0.90, 0.70, 0.22):
	set(v):
		color_c = v
		_changed()
@export_range(5.0, 600.0) var fall_speed := 55.0:
	set(v):
		fall_speed = v
		_changed()
## Sideways drift (px/s): positive toward the right.
@export_range(-600.0, 600.0) var wind := 30.0:
	set(v):
		wind = v
		_changed()
@export_range(0.0, 1.0) var density := 0.35:
	set(v):
		density = v
		_changed()
## Leaf length (px).
@export_range(2.0, 40.0) var leaf_size := 9.0:
	set(v):
		leaf_size = v
		_changed()
@export_range(0.0, 5.0) var spin := 1.0:
	set(v):
		spin = v
		_changed()
@export_range(0.0, 1.0) var sway := 0.6:
	set(v):
		sway = v
		_changed()
@export_group("Depth")
@export var far_plane := true:
	set(v):
		far_plane = v
		_queue_rebuild()
@export var far_z := -5:
	set(v):
		far_z = v
		_queue_rebuild()

func _init() -> void:
	z_index = 26

func get_effect_id() -> String:
	return "leaves"

func _build() -> void:
	var r := get_effect_rect()
	if far_plane:
		add_quad(shader("leaves"), r, far_z, 8.0, true).set_shader_parameter("depth", 1.0)
	add_quad(shader("leaves"), r).set_shader_parameter("depth", 0.0)

func _update_params() -> void:
	set_param(&"color_a", color_a)
	set_param(&"color_b", color_b)
	set_param(&"color_c", color_c)
	set_param(&"fall_speed", fall_speed)
	set_param(&"wind", wind)
	set_param(&"density", density)
	set_param(&"leaf_size", leaf_size)
	set_param(&"spin", spin)
	set_param(&"sway", sway)
