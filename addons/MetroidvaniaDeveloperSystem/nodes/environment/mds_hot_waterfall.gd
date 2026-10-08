@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/hot_waterfall.svg")
class_name MDSHotWaterfall
extends MDSEnvironmentEffect
## Hot water falls: scalding mineral water pouring down the rectangle, milky and pale where it
## runs thick, with a warm glow deep in it, streaks racing along it, white water at its lip and
## where it plunges, steam pouring off its whole length and billowing up from its foot, and the
## air around it wavering in the heat. By default it falls behind the terrain, so the rock it
## pours over frames it. Bodies of [member MDSEnvironmentEffect.affect_groups] under it are
## scalded every [member damage_interval] seconds, and pressed down with [member push_down].

## How fast the water falls (px/s).
@export_range(20.0, 3000.0) var flow_speed := 420.0:
	set(v):
		flow_speed = v
		_changed()
@export var water_color := Color(0.45, 0.80, 0.80, 0.78):
	set(v):
		water_color = v
		_changed()
@export var foam_color := Color(0.95, 0.98, 0.96):
	set(v):
		foam_color = v
		_changed()
## The warm light deep in the water and in the pool it plunges into.
@export var glow_color := Color(1.0, 0.72, 0.45, 0.45):
	set(v):
		glow_color = v
		_changed()
## How much the water bends what is behind it.
@export_range(0.0, 1.0) var refraction := 0.5:
	set(v):
		refraction = v
		_changed()
@export_group("Steam")
@export_range(0.0, 1.0) var steam := 0.8:
	set(v):
		steam = v
		_changed()
@export var steam_color := Color(0.94, 0.95, 0.96, 0.7):
	set(v):
		steam_color = v
		_changed()
## How fast the steam climbs (px/s).
@export_range(0.0, 400.0) var steam_rise := 60.0:
	set(v):
		steam_rise = v
		_changed()
## How far the steam drifts out to each side (px).
@export_range(0.0, 800.0) var steam_spread := 110.0:
	set(v):
		steam_spread = v
		_queue_rebuild()
## How far the steam climbs over the lip (px).
@export_range(0.0, 800.0) var steam_height := 140.0:
	set(v):
		steam_height = v
		_queue_rebuild()
## How far below the foot the steam billows (px).
@export_range(0.0, 600.0) var mist_depth := 90.0:
	set(v):
		mist_depth = v
		_queue_rebuild()
## The air wavering in the heat beside the sheet.
@export_range(0.0, 1.0) var shimmer := 0.6:
	set(v):
		shimmer = v
		_changed()
@export_group("Force")
## How hard (px/s) the falling water presses bodies under it down. 0: it doesn't.
@export_range(0.0, 2000.0) var push_down := 0.0
@export_group("Harm")
## Damage per hit to a body under it: it scalds. 0: none.
@export var damage := 4.0
@export_range(0.05, 10.0, 0.05) var damage_interval := 0.8

func _init() -> void:
	z_index = -3
	size = Vector2(120, 600)

func get_effect_id() -> String:
	return "hot_waterfall"

func _build() -> void:
	var quad := Rect2(Vector2(-steam_spread, -steam_height), size + Vector2(steam_spread * 2.0, steam_height + mist_depth))
	var m := add_quad(shader("hot_waterfall"), quad)
	m.set_shader_parameter("column", Vector4(steam_spread, steam_height, size.x, size.y))

func _update_params() -> void:
	set_param(&"flow_speed", flow_speed)
	set_param(&"water_color", water_color)
	set_param(&"foam_color", foam_color)
	set_param(&"glow_color", glow_color)
	set_param(&"refraction", refraction)
	set_param(&"steam", steam)
	set_param(&"steam_color", steam_color)
	set_param(&"steam_rise", steam_rise)
	set_param(&"steam_spread", steam_spread)
	set_param(&"shimmer", shimmer)

func _affect(body: Node2D, delta: float, strength: float) -> void:
	if push_down > 0.0:
		push_body(body, global_transform.basis_xform(Vector2.DOWN).normalized() * push_down * strength, delta)
	if damage > 0.0:
		hurt_body(body, damage * strength, damage_interval)
