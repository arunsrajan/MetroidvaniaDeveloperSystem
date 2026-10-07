@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/lava.svg")
class_name MDSLava
extends MDSEnvironmentEffect
## A pool of lava (or acid, or cursed ooze): a heaving surface with a bright skin, molten
## flow with crust plates drifting on it, bubbles bursting, a heat glow above and embers
## rising. Put the rectangle in a pit: its top edge is where the surface rests. Bodies of
## [member affect_groups] in it are hurt every [member damage_interval] seconds (connect
## [signal MDSEnvironmentEffect.body_hurt] to kill or respawn the player instead).

## A starting look; the colors below can be changed after.
enum Liquid { LAVA, MAGMA, ACID, CURSED }

@export var liquid: Liquid = Liquid.LAVA:
	set(v):
		if v != liquid:
			liquid = v
			_apply_liquid()
@export var crust_color := Color(0.16, 0.04, 0.03):
	set(v):
		crust_color = v
		_changed()
@export var hot_color := Color(0.95, 0.30, 0.06):
	set(v):
		hot_color = v
		_changed()
@export var bright_color := Color(1.0, 0.82, 0.42):
	set(v):
		bright_color = v
		_changed()
@export var glow_color := Color(1.0, 0.38, 0.10, 0.55):
	set(v):
		glow_color = v
		_changed()
@export_group("Motion")
@export_range(0.0, 40.0) var wave_height := 5.0:
	set(v):
		wave_height = v
		_changed()
@export_range(0.0, 5.0) var wave_speed := 1.0:
	set(v):
		wave_speed = v
		_changed()
@export_range(0.0, 5.0) var flow_speed := 1.0:
	set(v):
		flow_speed = v
		_changed()
## How much of the surface is crusted over.
@export_range(0.0, 1.0) var crust := 0.6:
	set(v):
		crust = v
		_changed()
@export_range(0.0, 1.0) var bubbles := 0.5:
	set(v):
		bubbles = v
		_changed()
@export_group("Above")
## How high the heat glow and the embers reach over the surface (px).
@export_range(0.0, 600.0) var glow_height := 90.0:
	set(v):
		glow_height = v
		_queue_rebuild()
@export_range(0.0, 1.0) var glow := 0.7:
	set(v):
		glow = v
		_changed()
@export_range(0.0, 1.0) var embers := 0.5:
	set(v):
		embers = v
		_changed()
@export_group("Harm")
## Damage per hit to a body in the pool. 0: none (just [signal MDSEnvironmentEffect.body_entered_effect]).
@export var damage := 10.0
@export_range(0.05, 10.0, 0.05) var damage_interval := 0.5
## How far (px) over the surface a body's position still counts as in it (a player's origin
## is often at its middle).
@export var contact_margin := 24.0

func _init() -> void:
	z_index = 2
	size = Vector2(480, 120)

func get_effect_id() -> String:
	return "lava"

func get_body_rect() -> Rect2:
	return Rect2(Vector2(0.0, -contact_margin), size + Vector2(0.0, contact_margin))

func _build() -> void:
	add_quad(shader("lava"), Rect2(Vector2(0.0, -glow_height), size + Vector2(0.0, glow_height)))

func _update_params() -> void:
	set_param(&"crust_color", crust_color)
	set_param(&"hot_color", hot_color)
	set_param(&"bright_color", bright_color)
	set_param(&"glow_color", glow_color)
	set_param(&"surface_y", glow_height)
	set_param(&"wave_height", wave_height)
	set_param(&"wave_speed", wave_speed)
	set_param(&"flow_speed", flow_speed)
	set_param(&"crust", crust)
	set_param(&"bubbles", bubbles)
	set_param(&"embers", embers)
	set_param(&"glow", glow)

func _apply_liquid() -> void:
	match liquid:
		Liquid.LAVA:
			crust_color = Color(0.16, 0.04, 0.03)
			hot_color = Color(0.95, 0.30, 0.06)
			bright_color = Color(1.0, 0.82, 0.42)
			glow_color = Color(1.0, 0.38, 0.10, 0.55)
			crust = 0.6
		Liquid.MAGMA:
			crust_color = Color(0.08, 0.05, 0.05)
			hot_color = Color(0.85, 0.16, 0.04)
			bright_color = Color(1.0, 0.62, 0.20)
			glow_color = Color(0.95, 0.25, 0.05, 0.5)
			crust = 0.9
		Liquid.ACID:
			crust_color = Color(0.10, 0.22, 0.05)
			hot_color = Color(0.45, 0.85, 0.12)
			bright_color = Color(0.85, 1.0, 0.45)
			glow_color = Color(0.5, 1.0, 0.2, 0.45)
			crust = 0.25
		Liquid.CURSED:
			crust_color = Color(0.10, 0.04, 0.16)
			hot_color = Color(0.55, 0.18, 0.85)
			bright_color = Color(0.92, 0.65, 1.0)
			glow_color = Color(0.6, 0.25, 1.0, 0.45)
			crust = 0.45

func _affect(body: Node2D, _delta: float, strength: float) -> void:
	if damage > 0.0:
		hurt_body(body, damage * strength, damage_interval)
