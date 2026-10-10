@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/wisps.svg")
class_name MDSWisps
extends MDSEnvironmentEffect
## Will-o'-wisps, like the Wisp Thicket's in Silksong: ghostly flames drifting on slow, looping
## paths, a flickering tongue of fire trailing behind each one and licking upward, a halo lighting
## the air around it. Blue by default; make them orange for a haunted forge.

## The flame.
@export var color := Color(0.35, 0.72, 1.0):
	set(v):
		color = v
		_changed()
## The heart of it.
@export var core_color := Color(0.88, 1.0, 1.0):
	set(v):
		core_color = v
		_changed()
@export_range(0.0, 1.0) var density := 0.6:
	set(v):
		density = v
		_changed()
## Average distance between wisps (px).
@export_range(60.0, 1200.0) var spacing := 220.0:
	set(v):
		spacing = v
		_changed()
@export_range(2.0, 40.0) var wisp_size := 8.0:
	set(v):
		wisp_size = v
		_changed()
## Radius of the light around each one (px).
@export_range(0.0, 200.0) var glow_radius := 44.0:
	set(v):
		glow_radius = v
		_changed()
@export_range(0.0, 5.0) var speed := 1.0:
	set(v):
		speed = v
		_changed()
## How long the flame trails behind.
@export_range(0.0, 3.0) var trail := 1.0:
	set(v):
		trail = v
		_changed()
@export_range(0.0, 1.0) var flicker := 0.6:
	set(v):
		flicker = v
		_changed()

func _init() -> void:
	z_index = 26

func get_effect_id() -> String:
	return "wisps"

func _build() -> void:
	add_quad(shader("wisps"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"core_color", core_color)
	set_param(&"density", density)
	set_param(&"spacing", spacing)
	set_param(&"wisp_size", wisp_size)
	set_param(&"glow_radius", glow_radius)
	set_param(&"speed", speed)
	set_param(&"trail", trail)
	set_param(&"flicker", flicker)
