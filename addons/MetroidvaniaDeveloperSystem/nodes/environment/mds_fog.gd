@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/fog.svg")
class_name MDSFog
extends MDSEnvironmentEffect
## Drifting fog or mist: warped banks rolling slowly sideways, over the whole rectangle or
## hugging its bottom ([member ground]: marsh mist, cave floor haze). Drawn in front of the
## room by default; set z_index below 0 to put it behind the terrain.

@export var color := Color(0.74, 0.79, 0.84, 1.0):
	set(v):
		color = v
		_changed()
@export_range(0.0, 1.0) var density := 0.5:
	set(v):
		density = v
		_changed()
## Drift (px/s): positive toward the right.
@export_range(-400.0, 400.0) var drift := 18.0:
	set(v):
		drift = v
		_changed()
## Size of the banks (px).
@export_range(40.0, 3000.0) var bank_size := 380.0:
	set(v):
		bank_size = v
		_changed()
## 0 even, 1 lying along the bottom.
@export_range(0.0, 1.0) var ground := 0.0:
	set(v):
		ground = v
		_changed()
## How high ground fog reaches, as a share of the height.
@export_range(0.05, 1.0) var ground_height := 0.35:
	set(v):
		ground_height = v
		_changed()

func _init() -> void:
	z_index = 25

func get_effect_id() -> String:
	return "fog"

func _build() -> void:
	add_quad(shader("fog"), get_effect_rect()).set_shader_parameter("edge_fade", 96.0)

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"density", density)
	set_param(&"speed", drift)
	set_param(&"scale", bank_size)
	set_param(&"ground", ground)
	set_param(&"ground_height", ground_height)
