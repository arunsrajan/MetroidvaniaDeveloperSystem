@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/incense_smoke.svg")
class_name MDSIncenseSmoke
extends MDSEnvironmentEffect
## Incense smoke, like the Citadel's choral chambers in Silksong: ribbons of smoke curling up from
## censers along the rectangle's bottom edge (put it on a censer or a brazier), spreading and
## fading as they rise, an ember glowing at each censer and flecks of golden ash glinting in it.

@export var color := Color(0.86, 0.82, 0.93, 0.6):
	set(v):
		color = v
		_changed()
## The censers' embers and the ash in the smoke.
@export var ember_color := Color(1.0, 0.74, 0.36):
	set(v):
		ember_color = v
		_changed()
## How many censers, spread along the bottom edge.
@export_range(1, 6) var plumes := 1:
	set(v):
		plumes = v
		_changed()
@export_range(0.0, 400.0) var rise_speed := 40.0:
	set(v):
		rise_speed = v
		_changed()
## How wide the smoke fans out as it rises.
@export_range(0.0, 1.0) var spread := 0.6:
	set(v):
		spread = v
		_changed()
## How much the ribbons curl.
@export_range(0.0, 2.0) var curl := 1.0:
	set(v):
		curl = v
		_changed()
@export_range(0.0, 1.0) var thickness := 0.6:
	set(v):
		thickness = v
		_changed()
## Golden ash in the smoke.
@export_range(0.0, 1.0) var flecks := 0.4:
	set(v):
		flecks = v
		_changed()
@export_range(0.0, 3.0) var sway := 1.0:
	set(v):
		sway = v
		_changed()

func _init() -> void:
	z_index = 4
	size = Vector2(240, 480)

func get_effect_id() -> String:
	return "incense_smoke"

func _build() -> void:
	add_quad(shader("incense_smoke"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"ember_color", ember_color)
	set_param(&"plumes", plumes)
	set_param(&"rise_speed", rise_speed)
	set_param(&"spread", spread)
	set_param(&"curl", curl)
	set_param(&"thickness", thickness)
	set_param(&"flecks", flecks)
	set_param(&"sway", sway)
