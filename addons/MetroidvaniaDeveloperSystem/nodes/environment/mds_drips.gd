@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/ceiling_drips.svg")
class_name MDSDrips
extends MDSEnvironmentEffect
## Dripping water, like the Wormways' and the Deep Docks' in Silksong: drops gathering under the
## rectangle's top edge (a ceiling), swelling, falling and splashing on its bottom edge (the
## floor) in a spreading ring and a few droplets, the ceiling glinting wet. Make it green for
## bile, or orange for molten drips.

@export var color := Color(0.72, 0.86, 0.96, 0.75):
	set(v):
		color = v
		_changed()
@export var highlight := Color(1.0, 1.0, 1.0, 0.9):
	set(v):
		highlight = v
		_changed()
## How many of the places a drop could form drip.
@export_range(0.0, 1.0) var density := 0.6:
	set(v):
		density = v
		_changed()
## Distance between drips (px).
@export_range(8.0, 600.0) var spacing := 70.0:
	set(v):
		spacing = v
		_changed()
@export_range(1.0, 12.0) var drop_size := 3.5:
	set(v):
		drop_size = v
		_changed()
@export_range(100.0, 6000.0) var gravity := 1200.0:
	set(v):
		gravity = v
		_changed()
## Average seconds a drop takes to gather.
@export_range(0.1, 20.0) var interval := 2.5:
	set(v):
		interval = v
		_changed()
@export_range(0.0, 1.0) var splash := 0.7:
	set(v):
		splash = v
		_changed()
## Glints along the ceiling.
@export_range(0.0, 1.0) var wet := 0.5:
	set(v):
		wet = v
		_changed()

func _init() -> void:
	z_index = 4

func get_effect_id() -> String:
	return "ceiling_drips"

func _build() -> void:
	add_quad(shader("ceiling_drips"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"highlight", highlight)
	set_param(&"density", density)
	set_param(&"spacing", spacing)
	set_param(&"drop_size", drop_size)
	set_param(&"gravity", gravity)
	set_param(&"interval", interval)
	set_param(&"splash", splash)
	set_param(&"wet", wet)
