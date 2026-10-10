@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/rockfall.svg")
class_name MDSRockfall
extends MDSEnvironmentEffect
## Falling rocks: stones break off at the top of the rectangle (put it under a ceiling) and drop,
## tumbling, to crash on the ground in a puff of dust and a spray of chips, piling up there as
## rubble (a heap resting on the rectangle's bottom edge: put that on the floor). Pebbles trickle
## down between them. With [member MDSEnvironmentEffect.activation] PLAYER_INSIDE the rocks start falling as
## the player comes near (a cave-in); MANUAL waits for [method MDSEnvironmentEffect.start]. With
## [member damage], bodies under it are hit every [member damage_interval] seconds.

@export var rock_color := Color(0.47, 0.42, 0.37):
	set(v):
		rock_color = v
		_changed()
@export var rock_dark := Color(0.20, 0.17, 0.15):
	set(v):
		rock_dark = v
		_changed()
@export var dust_color := Color(0.66, 0.60, 0.52, 0.75):
	set(v):
		dust_color = v
		_changed()
## How often rocks fall (0: never).
@export_range(0.0, 1.0) var rate := 0.5:
	set(v):
		rate = v
		_changed()
## The size of a big rock (px).
@export_range(4.0, 160.0) var rock_size := 18.0:
	set(v):
		rock_size = v
		_changed()
## How fast they fall (px/s²).
@export_range(100.0, 6000.0) var gravity := 1400.0:
	set(v):
		gravity = v
		_changed()
@export_group("Rubble")
## How much rubble lies on the ground.
@export_range(0.0, 1.0) var rubble := 0.7:
	set(v):
		rubble = v
		_changed()
## How high the rubble heap rises (px).
@export_range(0.0, 400.0) var rubble_height := 60.0:
	set(v):
		rubble_height = v
		_changed()
@export_range(0.0, 1.0) var dust := 0.7:
	set(v):
		dust = v
		_changed()
@export_range(0.0, 1.0) var pebbles := 0.5:
	set(v):
		pebbles = v
		_changed()
@export_group("Harm")
## Damage per hit to a body under the falling rocks. 0: none (scenery).
@export var damage := 0.0
@export_range(0.05, 10.0, 0.05) var damage_interval := 1.0

func _init() -> void:
	z_index = 1
	size = Vector2(360, 480)

func get_effect_id() -> String:
	return "rockfall"

func _build() -> void:
	add_quad(shader("rockfall"), get_effect_rect())

func _update_params() -> void:
	set_param(&"rock_color", rock_color)
	set_param(&"rock_dark", rock_dark)
	set_param(&"dust_color", dust_color)
	set_param(&"rate", rate)
	set_param(&"rock_size", rock_size)
	set_param(&"gravity", gravity)
	set_param(&"rubble", rubble)
	set_param(&"rubble_height", rubble_height)
	set_param(&"dust", dust)
	set_param(&"pebbles", pebbles)

func _affect(body: Node2D, _delta: float, strength: float) -> void:
	if damage > 0.0 and rate > 0.0:
		hurt_body(body, damage * strength, damage_interval)
