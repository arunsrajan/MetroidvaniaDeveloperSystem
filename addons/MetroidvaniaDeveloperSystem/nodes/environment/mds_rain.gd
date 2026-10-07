@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/rain.svg")
class_name MDSRain
extends MDSEnvironmentEffect
## Rain: streaks at three depths falling at an angle, splashes along the bottom of the
## rectangle (put it on the ground) and a low mist. A far plane falls behind the terrain.
## Pair it with [MDSLightning] for a storm (the "storm" weather preset does).

## Lean of the rain (degrees): positive falls toward the right.
@export_range(-60.0, 60.0) var angle := 12.0:
	set(v):
		angle = v
		_changed()
## How fast the drops fall (px/s).
@export_range(50.0, 4000.0) var fall_speed := 1100.0:
	set(v):
		fall_speed = v
		_changed()
@export_range(0.0, 1.0) var density := 0.55:
	set(v):
		density = v
		_changed()
@export_range(2.0, 200.0) var drop_length := 34.0:
	set(v):
		drop_length = v
		_changed()
@export_range(0.5, 8.0) var drop_width := 1.4:
	set(v):
		drop_width = v
		_changed()
@export var color := Color(0.72, 0.80, 0.90, 0.55):
	set(v):
		color = v
		_changed()
## Splashes along the bottom edge.
@export_range(0.0, 1.0) var splashes := 0.6:
	set(v):
		splashes = v
		_changed()
## A mist hanging low.
@export_range(0.0, 1.0) var mist := 0.15:
	set(v):
		mist = v
		_changed()
@export var mist_color := Color(0.45, 0.52, 0.60):
	set(v):
		mist_color = v
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
	z_index = 30

func get_effect_id() -> String:
	return "rain"

func _build() -> void:
	var r := get_effect_rect()
	if far_plane:
		var far := add_quad(shader("rain"), r, far_z, 5.0, true)
		far.set_shader_parameter("depth", 1.0)
	add_quad(shader("rain"), r).set_shader_parameter("depth", 0.0)

func _update_params() -> void:
	set_param(&"angle_deg", angle)
	set_param(&"speed", fall_speed)
	set_param(&"density", density)
	set_param(&"drop_length", drop_length)
	set_param(&"drop_width", drop_width)
	set_param(&"color", color)
	set_param(&"splashes", splashes)
	set_param(&"mist", mist)
	set_param(&"mist_color", mist_color)
