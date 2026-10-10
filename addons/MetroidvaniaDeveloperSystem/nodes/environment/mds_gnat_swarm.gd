@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/gnat_swarm.svg")
class_name MDSGnatSwarm
extends MDSEnvironmentEffect
## A gnat swarm, like Bilewater's in Silksong: clouds of tiny gnats buzzing around swarm centres
## that drift about, wings catching the light. A swarm near a node of
## [member MDSEnvironmentEffect.affect_groups] (within [member lure_radius] px) is drawn to it and
## gathers around its head; [member lure] 0 leaves them be.

@export var color := Color(0.08, 0.08, 0.05, 0.9):
	set(v):
		color = v
		_changed()
## Their wings catching the light (its alpha: how much).
@export var glint_color := Color(0.78, 0.82, 0.62, 0.6):
	set(v):
		glint_color = v
		_changed()
## How many of the places a swarm could be have one.
@export_range(0.0, 1.0) var swarm_density := 0.5:
	set(v):
		swarm_density = v
		_changed()
## Average distance between swarms (px).
@export_range(80.0, 2000.0) var swarm_spacing := 320.0:
	set(v):
		swarm_spacing = v
		_changed()
## How far a swarm spreads (px).
@export_range(5.0, 300.0) var swarm_size := 55.0:
	set(v):
		swarm_size = v
		_changed()
## Gnats in a swarm.
@export_range(1, 48) var gnats := 22:
	set(v):
		gnats = v
		_changed()
@export_range(0.5, 6.0) var gnat_size := 1.4:
	set(v):
		gnat_size = v
		_changed()
@export_group("Motion")
## How fast they buzz about.
@export_range(0.0, 5.0) var buzz := 1.0:
	set(v):
		buzz = v
		_changed()
## How fast the swarms drift.
@export_range(0.0, 5.0) var drift := 1.0:
	set(v):
		drift = v
		_changed()
## How much a swarm is drawn to a body near it.
@export_range(0.0, 1.0) var lure := 0.6:
	set(v):
		lure = v
		_changed()
@export_range(0.0, 1500.0) var lure_radius := 260.0:
	set(v):
		lure_radius = v
		_changed()

func _init() -> void:
	z_index = 26

func get_effect_id() -> String:
	return "gnat_swarm"

func _build() -> void:
	add_quad(shader("gnat_swarm"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color", color)
	set_param(&"glint_color", glint_color)
	set_param(&"swarm_density", swarm_density)
	set_param(&"swarm_spacing", swarm_spacing)
	set_param(&"swarm_size", swarm_size)
	set_param(&"gnats", gnats)
	set_param(&"gnat_size", gnat_size)
	set_param(&"buzz", buzz)
	set_param(&"drift", drift)
	set_param(&"lure", lure)
	set_param(&"lure_radius", lure_radius)

func _tick(_delta: float) -> void:
	if lure > 0.0 and lure_radius > 0.0:
		send_bodies(lure_radius)
	else:
		set_param(&"body_count", 0)
