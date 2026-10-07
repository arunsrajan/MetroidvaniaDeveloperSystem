@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/embers.svg")
class_name MDSEmbers
extends MDSEnvironmentEffect
## Embers rising from fires below, wobbling and flickering out as they cool (a volcano, a
## burning village, a forge), or ash and soot drifting down. A far plane rises behind the
## terrain.

## A starting look; the settings below can be changed after.
enum Kind { EMBERS, ASH, SPARKS }

@export var kind: Kind = Kind.EMBERS:
	set(v):
		if v != kind:
			kind = v
			_apply_kind()
@export var hot_color := Color(1.0, 0.80, 0.36):
	set(v):
		hot_color = v
		_changed()
@export var cool_color := Color(0.92, 0.22, 0.06):
	set(v):
		cool_color = v
		_changed()
## How fast they rise (px/s); negative: they fall.
@export_range(-600.0, 600.0) var rise_speed := 70.0:
	set(v):
		rise_speed = v
		_changed()
## Sideways drift (px/s).
@export_range(-600.0, 600.0) var drift := 15.0:
	set(v):
		drift = v
		_changed()
@export_range(0.0, 1.0) var density := 0.3:
	set(v):
		density = v
		_changed()
@export_range(0.5, 10.0) var mote_size := 2.2:
	set(v):
		mote_size = v
		_changed()
@export_range(0.0, 60.0) var wobble := 18.0:
	set(v):
		wobble = v
		_changed()
## A soft halo around each one.
@export_range(0.0, 1.0) var glow := 0.6:
	set(v):
		glow = v
		_changed()
@export_range(0.0, 1.0) var flicker := 0.7:
	set(v):
		flicker = v
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
	return "embers"

func _build() -> void:
	var r := get_effect_rect()
	if far_plane:
		add_quad(shader("embers"), r, far_z, 4.0, true).set_shader_parameter("depth", 1.0)
	add_quad(shader("embers"), r).set_shader_parameter("depth", 0.0)

func _update_params() -> void:
	set_param(&"hot_color", hot_color)
	set_param(&"cool_color", cool_color)
	set_param(&"rise_speed", rise_speed)
	set_param(&"drift", drift)
	set_param(&"density", density)
	set_param(&"size", mote_size)
	set_param(&"wobble", wobble)
	set_param(&"glow", glow)
	set_param(&"flicker", flicker)

func _apply_kind() -> void:
	match kind:
		Kind.EMBERS:
			hot_color = Color(1.0, 0.80, 0.36)
			cool_color = Color(0.92, 0.22, 0.06)
			rise_speed = 70.0
			glow = 0.6
			flicker = 0.7
			mote_size = 2.2
		Kind.ASH:
			hot_color = Color(0.55, 0.55, 0.56)
			cool_color = Color(0.30, 0.30, 0.32)
			rise_speed = -45.0
			glow = 0.0
			flicker = 0.0
			mote_size = 2.6
		Kind.SPARKS:
			hot_color = Color(1.0, 0.95, 0.7)
			cool_color = Color(1.0, 0.6, 0.2)
			rise_speed = 160.0
			glow = 0.9
			flicker = 1.0
			mote_size = 1.5
