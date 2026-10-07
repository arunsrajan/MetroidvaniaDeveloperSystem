@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/light_shafts.svg")
class_name MDSLightShafts
extends MDSEnvironmentEffect
## Shafts of light slanting down from openings above (god rays), shimmering slowly, with dust
## motes drifting in them. Put the rectangle's top edge where the light comes in.

@export var color := Color(1.0, 0.94, 0.78, 0.6):
	set(v):
		color = v
		_changed()
## Slant (degrees): positive leans toward the right as the light goes down.
@export_range(-60.0, 60.0) var angle := 18.0:
	set(v):
		angle = v
		_changed()
## Average distance between shafts (px).
@export_range(20.0, 2000.0) var spread := 150.0:
	set(v):
		spread = v
		_changed()
@export_range(0.0, 1.0) var softness := 0.5:
	set(v):
		softness = v
		_changed()
## How far down they reach, as a share of the height.
@export_range(0.05, 1.0) var reach := 0.8:
	set(v):
		reach = v
		_changed()
@export_range(0.0, 1.0) var shimmer := 0.5:
	set(v):
		shimmer = v
		_changed()
## Dust motes in the light.
@export_range(0.0, 1.0) var motes := 0.4:
	set(v):
		motes = v
		_changed()

func _init() -> void:
	z_index = 24

func get_effect_id() -> String:
	return "light_shafts"

func _build() -> void:
	add_quad(shader("light_shafts"), get_effect_rect()).set_shader_parameter("edge_fade", 64.0)

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"angle_deg", angle)
	set_param(&"spread", spread)
	set_param(&"softness", softness)
	set_param(&"reach", reach)
	set_param(&"shimmer", shimmer)
	set_param(&"motes", motes)
