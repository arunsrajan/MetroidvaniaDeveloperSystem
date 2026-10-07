@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/snow.svg")
class_name MDSSnowfall
extends MDSEnvironmentEffect
## Snowfall: soft flakes at four depths drifting down, swaying, carried by the wind. Turn up
## [member blizzard] for driven snow streaking across. A far plane falls behind the terrain.

## How fast the flakes fall (px/s).
@export_range(5.0, 1000.0) var fall_speed := 70.0:
	set(v):
		fall_speed = v
		_changed()
## Sideways drift (px/s): positive toward the right.
@export_range(-600.0, 600.0) var wind := 25.0:
	set(v):
		wind = v
		_changed()
@export_range(0.0, 1.0) var sway := 0.5:
	set(v):
		sway = v
		_changed()
@export_range(0.5, 12.0) var flake_size := 3.0:
	set(v):
		flake_size = v
		_changed()
@export_range(0.0, 1.0) var density := 0.5:
	set(v):
		density = v
		_changed()
@export var color := Color(0.96, 0.97, 1.0, 0.9):
	set(v):
		color = v
		_changed()
## Driven snow: faster, slanted flakes and streaks racing along.
@export_range(0.0, 1.0) var blizzard := 0.0:
	set(v):
		blizzard = v
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
@export_group("Wind")
## With a blizzard, how hard (px/s) the wind shoves bodies along it. 0: never.
@export_range(0.0, 1000.0) var push := 0.0

func _init() -> void:
	z_index = 30

func get_effect_id() -> String:
	return "snow"

func _build() -> void:
	var r := get_effect_rect()
	if far_plane:
		add_quad(shader("snow"), r, far_z, 3.0, true).set_shader_parameter("depth", 1.0)
	add_quad(shader("snow"), r).set_shader_parameter("depth", 0.0)

func _update_params() -> void:
	set_param(&"fall_speed", fall_speed)
	set_param(&"wind", wind)
	set_param(&"sway", sway)
	set_param(&"flake_size", flake_size)
	set_param(&"density", density)
	set_param(&"color", color)
	set_param(&"blizzard", blizzard)

func _affect(body: Node2D, delta: float, strength: float) -> void:
	if push > 0.0 and blizzard > 0.0 and wind != 0.0:
		push_body(body, global_transform.basis_xform(Vector2(signf(wind), 0.0)).normalized() * push * blizzard * strength, delta)
