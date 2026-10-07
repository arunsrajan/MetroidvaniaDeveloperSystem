@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/dust_storm.svg")
class_name MDSDustStorm
extends MDSEnvironmentEffect
## A dust storm blowing from one side: banks of dust billowing past in gusts, wisps racing
## ahead of them, dark grit and pale motes driven along (the wind-scoured wastes of a desert
## area). A far plane behind the terrain gives it depth. With [member push], the wind shoves
## the bodies of [member affect_groups] downwind, harder in gusts.

enum Toward { LEFT, RIGHT }

## Which way the wind blows.
@export var blows_toward: Toward = Toward.RIGHT:
	set(v):
		blows_toward = v
		_changed()
## How fast the dust travels (px/s).
@export_range(0.0, 2000.0) var wind_speed := 420.0:
	set(v):
		wind_speed = v
		_changed()
## How thick the banks of dust are.
@export_range(0.0, 1.0) var density := 0.6:
	set(v):
		density = v
		_changed()
## Size of the banks (px).
@export_range(60.0, 3000.0) var bank_size := 520.0:
	set(v):
		bank_size = v
		_changed()
## Grit and motes driven along.
@export_range(0.0, 1.0) var grit := 0.6:
	set(v):
		grit = v
		_changed()
## How much the wind rises and falls: 0 steady, 1 strong gusts.
@export_range(0.0, 1.0) var gustiness := 0.5:
	set(v):
		gustiness = v
		_changed()
@export_range(0.0, 1.0) var opacity := 0.85:
	set(v):
		opacity = v
		_changed()
@export_group("Colors")
@export var dust_color := Color(0.63, 0.63, 0.61):
	set(v):
		dust_color = v
		_changed()
@export var shade_color := Color(0.22, 0.26, 0.30):
	set(v):
		shade_color = v
		_changed()
@export var grit_color := Color(0.06, 0.06, 0.07):
	set(v):
		grit_color = v
		_changed()
@export var mote_color := Color(0.93, 0.94, 0.96):
	set(v):
		mote_color = v
		_changed()
@export_group("Depth")
## A second, fainter storm behind the terrain.
@export var far_plane := true:
	set(v):
		far_plane = v
		_queue_rebuild()
## z of the far plane (the room's terrain is at 0, its background below -5).
@export var far_z := -5:
	set(v):
		far_z = v
		_queue_rebuild()
@export_group("Wind")
## How hard (px/s) the wind shoves bodies downwind at full strength; gusts shove harder.
## 0: it only blows dust.
@export_range(0.0, 1000.0) var push := 110.0

func _init() -> void:
	z_index = 30

func get_effect_id() -> String:
	return "dust_storm"

## 1 toward the right, -1 toward the left.
func get_direction() -> float:
	return -1.0 if blows_toward == Toward.LEFT else 1.0

func _build() -> void:
	var r := get_effect_rect()
	if far_plane:
		add_quad(shader("dust_storm"), r, far_z, 7.0, true).set_shader_parameter("depth", 1.0)
	add_quad(shader("dust_storm"), r).set_shader_parameter("depth", 0.0)

func _update_params() -> void:
	set_param(&"direction", get_direction())
	set_param(&"speed", wind_speed)
	set_param(&"density", density)
	set_param(&"scale", bank_size)
	set_param(&"grit", grit)
	set_param(&"gustiness", gustiness)
	set_param(&"opacity", opacity)
	set_param(&"dust_color", dust_color)
	set_param(&"shade_color", shade_color)
	set_param(&"grit_color", grit_color)
	set_param(&"mote_color", mote_color)

## The wind's strength now (1 steady, more in a gust): what [member push] is multiplied by.
func gust_now() -> float:
	var t := Time.get_ticks_msec() / 1000.0 + seed_value * 3.1
	var g := 0.5 + 0.5 * sin(t * 1.3) * sin(t * 0.37 + 1.0)
	return lerpf(1.0, 0.45 + 1.1 * g, gustiness)

func _affect(body: Node2D, delta: float, strength: float) -> void:
	if push > 0.0:
		push_body(body, global_transform.basis_xform(Vector2(get_direction(), 0.0)).normalized() * push * strength * gust_now(), delta)
