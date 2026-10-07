@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/heat_haze.svg")
class_name MDSHeatHaze
extends MDSEnvironmentEffect
## Heat haze: everything drawn behind the rectangle shimmers, rippling upward, strongest low
## down. Put it over lava, a forge or a desert floor. It bends what has a lower z_index than
## its own (28 by default: the whole room).

## How far things are bent (px).
@export_range(0.0, 40.0) var strength := 4.0:
	set(v):
		strength = v
		_changed()
## How fast the ripples rise (px/s).
@export_range(0.0, 600.0) var rise_speed := 40.0:
	set(v):
		rise_speed = v
		_changed()
## Size of the ripples (px).
@export_range(4.0, 600.0) var ripple_size := 60.0:
	set(v):
		ripple_size = v
		_changed()
## 0 even, 1 strongest along the bottom and gone at the top.
@export_range(0.0, 1.0) var rise := 0.6:
	set(v):
		rise = v
		_changed()
## A cast over the haze (alpha: how much).
@export var tint := Color(1.0, 0.62, 0.40, 0.0):
	set(v):
		tint = v
		_changed()

func _init() -> void:
	z_index = 28
	size = Vector2(480, 240)

func get_effect_id() -> String:
	return "heat_haze"

func _build() -> void:
	add_quad(shader("heat_haze"), get_effect_rect())

func _update_params() -> void:
	set_param(&"strength", strength)
	set_param(&"speed", rise_speed)
	set_param(&"scale", ripple_size)
	set_param(&"rise", rise)
	set_param(&"tint", tint)
