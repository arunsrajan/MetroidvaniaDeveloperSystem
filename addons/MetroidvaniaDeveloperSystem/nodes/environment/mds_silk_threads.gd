@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/silk_threads.svg")
class_name MDSSilkThreads
extends MDSEnvironmentEffect
## Silk threads, like the Weavenest's in Silksong: strands of silk drifting and turning slowly in
## the air, light running along them, and threads hanging from the rectangle's top edge, swaying,
## a bead of silk at the end of each.

@export var color := Color(0.96, 0.93, 1.0, 0.85):
	set(v):
		color = v
		_changed()
## The light running along them.
@export var glint_color := Color(1.0, 0.82, 0.92):
	set(v):
		glint_color = v
		_changed()
## How many strands drift in the air.
@export_range(0.0, 1.0) var density := 0.6:
	set(v):
		density = v
		_changed()
## Average distance between drifting strands (px).
@export_range(40.0, 1000.0) var spacing := 150.0:
	set(v):
		spacing = v
		_changed()
@export_range(10.0, 400.0) var strand_length := 120.0:
	set(v):
		strand_length = v
		_changed()
@export_group("Hanging")
## How many threads hang from the top edge (0: none).
@export_range(0.0, 1.0) var hanging := 0.5:
	set(v):
		hanging = v
		_changed()
## Distance between hanging threads (px).
@export_range(10.0, 400.0) var hang_spacing := 70.0:
	set(v):
		hang_spacing = v
		_changed()
## How far they hang, a share of the height.
@export_range(0.05, 1.0) var hang_length := 0.45:
	set(v):
		hang_length = v
		_changed()
@export_group("Motion")
@export_range(0.0, 3.0) var sway := 1.0:
	set(v):
		sway = v
		_changed()
@export_range(0.0, 5.0) var speed := 1.0:
	set(v):
		speed = v
		_changed()
@export_range(0.0, 1.0) var glow := 0.5:
	set(v):
		glow = v
		_changed()
@export_range(0.3, 4.0) var thickness := 1.0:
	set(v):
		thickness = v
		_changed()

func _init() -> void:
	z_index = 24

func get_effect_id() -> String:
	return "silk_threads"

func _build() -> void:
	add_quad(shader("silk_threads"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"glint_color", glint_color)
	set_param(&"density", density)
	set_param(&"spacing", spacing)
	set_param(&"strand_length", strand_length)
	set_param(&"hanging", hanging)
	set_param(&"hang_spacing", hang_spacing)
	set_param(&"hang_length", hang_length)
	set_param(&"sway", sway)
	set_param(&"speed", speed)
	set_param(&"glow", glow)
	set_param(&"thickness", thickness)
