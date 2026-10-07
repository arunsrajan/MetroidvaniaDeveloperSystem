@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/fireflies.svg")
class_name MDSFireflies
extends MDSEnvironmentEffect
## Fireflies, glowing spores or glitter: motes wandering on slow loops, pulsing on and off.
## Pick two colors (each mote takes one). A far plane drifts behind the terrain.

@export var color := Color(0.85, 1.0, 0.45):
	set(v):
		color = v
		_changed()
@export var color_b := Color(0.55, 1.0, 0.75):
	set(v):
		color_b = v
		_changed()
@export_range(0.0, 1.0) var density := 0.35:
	set(v):
		density = v
		_changed()
## Average distance between motes (px).
@export_range(20.0, 600.0) var spacing := 90.0:
	set(v):
		spacing = v
		_changed()
@export_range(0.5, 10.0) var mote_size := 2.0:
	set(v):
		mote_size = v
		_changed()
## Radius of each one's glow (px).
@export_range(0.0, 60.0) var glow_radius := 9.0:
	set(v):
		glow_radius = v
		_changed()
## How fast they wander.
@export_range(0.0, 5.0) var speed := 1.0:
	set(v):
		speed = v
		_changed()
## 0 always lit, 1 they blink on and off.
@export_range(0.0, 1.0) var blink := 0.7:
	set(v):
		blink = v
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
	return "fireflies"

func _build() -> void:
	var r := get_effect_rect()
	if far_plane:
		add_quad(shader("fireflies"), r, far_z, 6.0, true).set_shader_parameter("depth", 1.0)
	add_quad(shader("fireflies"), r).set_shader_parameter("depth", 0.0)

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"color_b", color_b)
	set_param(&"density", density)
	set_param(&"spacing", spacing)
	set_param(&"size", mote_size)
	set_param(&"glow_radius", glow_radius)
	set_param(&"speed", speed)
	set_param(&"blink", blink)
