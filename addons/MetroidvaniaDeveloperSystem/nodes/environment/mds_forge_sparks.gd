@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/forge_sparks.svg")
class_name MDSForgeSparks
extends MDSEnvironmentEffect
## Forge sparks, like the Deep Docks' in Silksong: sparks spraying from a [member source] (a forge,
## a grinding wheel, a cut chain; the middle of the top edge by default) in a fan, arcing down,
## bouncing off the rectangle's bottom edge (put it on the floor) and dying out, white-hot when
## thrown and cooling to red, a glow pulsing at the source. A steady stream, or bursts (a hammer
## striking) every [member burst_interval] seconds. With [member damage] they burn the bodies
## under them.

@export var color_hot := Color(1.0, 0.96, 0.76):
	set(v):
		color_hot = v
		_changed()
@export var color := Color(1.0, 0.62, 0.2):
	set(v):
		color = v
		_changed()
@export var color_cool := Color(0.82, 0.18, 0.05):
	set(v):
		color_cool = v
		_changed()
## Where they come from, a share of the rectangle ((0.5, 0): the middle of the top edge).
@export var source := Vector2(0.5, 0.0):
	set(v):
		source = v
		_changed()
## How many sparks are in the air at once.
@export_range(1, 128) var count := 48:
	set(v):
		count = v
		_changed()
## How fast the stream runs.
@export_range(0.0, 4.0) var rate := 1.0:
	set(v):
		rate = v
		_changed()
## Which way they spray, in degrees from straight down (positive: to the right; 180: up).
@export_range(-180.0, 180.0) var angle := 0.0:
	set(v):
		angle = v
		_changed()
## How wide the fan is, in degrees.
@export_range(0.0, 360.0) var spread := 70.0:
	set(v):
		spread = v
		_changed()
@export_range(0.0, 3000.0) var speed := 420.0:
	set(v):
		speed = v
		_changed()
@export_range(0.0, 6000.0) var gravity := 900.0:
	set(v):
		gravity = v
		_changed()
## How much of their speed they keep after hitting the bottom edge (0: they land and slide).
@export_range(0.0, 1.0) var bounce := 0.35:
	set(v):
		bounce = v
		_changed()
## How long one lives (s).
@export_range(0.1, 6.0) var life := 1.3:
	set(v):
		life = v
		_changed()
@export_range(1.0, 60.0) var spark_length := 10.0:
	set(v):
		spark_length = v
		_changed()
@export_range(0.0, 1.0) var glow := 0.6:
	set(v):
		glow = v
		_changed()
@export_group("Bursts")
## Bursts every [member burst_interval] seconds instead of a steady stream.
@export var bursts := false:
	set(v):
		bursts = v
		_changed()
@export_range(0.1, 20.0) var burst_interval := 1.6:
	set(v):
		burst_interval = v
		_changed()
@export_group("Harm")
## Damage per hit to a body under the sparks. 0: none (scenery).
@export var damage := 0.0
@export_range(0.05, 10.0, 0.05) var damage_interval := 0.6

func _init() -> void:
	z_index = 25
	size = Vector2(360, 420)

func get_effect_id() -> String:
	return "forge_sparks"

func _build() -> void:
	add_quad(shader("forge_sparks"), get_effect_rect())

func _update_params() -> void:
	set_param(&"color_hot", color_hot)
	set_param(&"color", color)
	set_param(&"color_cool", color_cool)
	set_param(&"source", source)
	set_param(&"count", count)
	set_param(&"rate", rate)
	set_param(&"angle", angle)
	set_param(&"spread", spread)
	set_param(&"speed", speed)
	set_param(&"gravity", gravity)
	set_param(&"bounce", bounce)
	set_param(&"life", life)
	set_param(&"spark_length", spark_length)
	set_param(&"glow", glow)
	set_param(&"burst", 1.0 if bursts else 0.0)
	set_param(&"burst_interval", burst_interval)

func _affect(body: Node2D, _delta: float, strength: float) -> void:
	if damage > 0.0 and count > 0:
		hurt_body(body, damage * strength, damage_interval)
