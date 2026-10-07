@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/waterfall.svg")
class_name MDSWaterfall
extends MDSEnvironmentEffect
## A waterfall: a sheet of water pouring down the rectangle with streaks racing along it,
## ragged sides, white water at the lip and where it plunges, and mist billowing out at its
## foot. What is behind shows through, bent by the water. By default it falls behind the
## terrain, so the rock it pours over frames it. With [member push_down], bodies under it are
## pressed down.

## How fast the water falls (px/s).
@export_range(20.0, 3000.0) var flow_speed := 520.0:
	set(v):
		flow_speed = v
		_changed()
@export var water_color := Color(0.42, 0.70, 0.85, 0.72):
	set(v):
		water_color = v
		_changed()
@export var foam_color := Color(0.92, 0.97, 1.0):
	set(v):
		foam_color = v
		_changed()
## How much the water bends what is behind it.
@export_range(0.0, 1.0) var refraction := 0.6:
	set(v):
		refraction = v
		_changed()
@export_group("Mist")
@export_range(0.0, 1.0) var mist := 0.7:
	set(v):
		mist = v
		_changed()
@export var mist_color := Color(0.85, 0.92, 0.97, 0.6):
	set(v):
		mist_color = v
		_changed()
## How far the mist spreads to each side of the foot (px).
@export_range(0.0, 800.0) var mist_spread := 90.0:
	set(v):
		mist_spread = v
		_queue_rebuild()
## How far below the foot the mist reaches (px).
@export_range(0.0, 600.0) var mist_depth := 70.0:
	set(v):
		mist_depth = v
		_queue_rebuild()
@export_group("Force")
## How hard (px/s) the falling water presses bodies under it down. 0: it doesn't.
@export_range(0.0, 2000.0) var push_down := 0.0

func _init() -> void:
	z_index = -3
	size = Vector2(120, 600)

func get_effect_id() -> String:
	return "waterfall"

func _build() -> void:
	var quad := Rect2(Vector2(-mist_spread, 0.0), size + Vector2(mist_spread * 2.0, mist_depth))
	var m := add_quad(shader("waterfall"), quad)
	m.set_shader_parameter("column", Vector4(mist_spread, 0.0, size.x, size.y))

func _update_params() -> void:
	set_param(&"flow_speed", flow_speed)
	set_param(&"water_color", water_color)
	set_param(&"foam_color", foam_color)
	set_param(&"refraction", refraction)
	set_param(&"mist", mist)
	set_param(&"mist_color", mist_color)

func _affect(body: Node2D, delta: float, strength: float) -> void:
	if push_down > 0.0:
		push_body(body, global_transform.basis_xform(Vector2.DOWN).normalized() * push_down * strength, delta)
