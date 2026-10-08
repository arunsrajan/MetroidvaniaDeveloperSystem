@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/lava_fall.svg")
class_name MDSLavaFall
extends MDSEnvironmentEffect
## Lava falls: molten rock pouring over a ledge down the rectangle, slow and thick. A white-hot
## core with orange streaks racing down it, dark crust forming as it falls and breaking up
## with glowing cracks, heavy blobs bulging at its sides, a bright lip where it pours over and
## a splash where it lands throwing molten drops, a heat glow around it, embers rising and the
## air wavering in the heat. [member liquid] switches it to magma, acid or cursed ooze. By
## default it falls behind the terrain, so the rock frames it. Bodies of
## [member MDSEnvironmentEffect.affect_groups] in it are burnt every [member damage_interval]
## seconds (connect [signal MDSEnvironmentEffect.body_hurt] to kill or respawn the player
## instead).

@export var liquid: MDSLava.Liquid = MDSLava.Liquid.LAVA:
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
## How fast it falls in its middle (px/s); its sides drag slower.
@export_range(10.0, 2000.0) var flow_speed := 170.0:
	set(v):
		flow_speed = v
		_changed()
## How much crust forms on it as it falls.
@export_range(0.0, 1.0) var crust := 0.45:
	set(v):
		crust = v
		_changed()
@export_group("Around")
@export_range(0.0, 1.0) var glow := 0.8:
	set(v):
		glow = v
		_changed()
## How far the glow, the embers and the wavering air reach out to each side (px).
@export_range(0.0, 800.0) var glow_spread := 90.0:
	set(v):
		glow_spread = v
		_queue_rebuild()
## Molten drops thrown out where it lands.
@export_range(0.0, 1.0) var splash := 0.7:
	set(v):
		splash = v
		_changed()
## How far below its foot the splash and the glow reach (px).
@export_range(0.0, 600.0) var splash_depth := 60.0:
	set(v):
		splash_depth = v
		_queue_rebuild()
@export_range(0.0, 1.0) var embers := 0.6:
	set(v):
		embers = v
		_changed()
@export_range(0.0, 1.0) var heat_haze := 0.5:
	set(v):
		heat_haze = v
		_changed()
@export_group("Harm")
## Damage per hit to a body in it. 0: none (just [signal MDSEnvironmentEffect.body_entered_effect]).
@export var damage := 15.0
@export_range(0.05, 10.0, 0.05) var damage_interval := 0.4
## How hard (px/s) the falling rock presses bodies in it down. 0: it doesn't.
@export_range(0.0, 2000.0) var push_down := 0.0

## Room above the lip for the glow and the drops thrown up (px).
const HEADROOM := 40.0

func _init() -> void:
	z_index = -3
	size = Vector2(110, 600)

func get_effect_id() -> String:
	return "lava_fall"

func _build() -> void:
	var drops := maxf(splash_depth, 0.0)
	var quad := Rect2(Vector2(-glow_spread, -HEADROOM), size + Vector2(glow_spread * 2.0, HEADROOM + drops))
	var m := add_quad(shader("lava_fall"), quad)
	m.set_shader_parameter("column", Vector4(glow_spread, HEADROOM, size.x, size.y))

func _update_params() -> void:
	set_param(&"crust_color", crust_color)
	set_param(&"hot_color", hot_color)
	set_param(&"bright_color", bright_color)
	set_param(&"glow_color", glow_color)
	set_param(&"flow_speed", flow_speed)
	set_param(&"crust", crust)
	set_param(&"glow", glow)
	set_param(&"glow_spread", glow_spread)
	set_param(&"splash", splash)
	set_param(&"embers", embers)
	set_param(&"heat_haze", heat_haze)

func _apply_liquid() -> void:
	match liquid:
		MDSLava.Liquid.LAVA:
			crust_color = Color(0.16, 0.04, 0.03)
			hot_color = Color(0.95, 0.30, 0.06)
			bright_color = Color(1.0, 0.82, 0.42)
			glow_color = Color(1.0, 0.38, 0.10, 0.55)
			crust = 0.45
		MDSLava.Liquid.MAGMA:
			crust_color = Color(0.08, 0.05, 0.05)
			hot_color = Color(0.85, 0.16, 0.04)
			bright_color = Color(1.0, 0.62, 0.20)
			glow_color = Color(0.95, 0.25, 0.05, 0.5)
			crust = 0.8
		MDSLava.Liquid.ACID:
			crust_color = Color(0.10, 0.22, 0.05)
			hot_color = Color(0.45, 0.85, 0.12)
			bright_color = Color(0.85, 1.0, 0.45)
			glow_color = Color(0.5, 1.0, 0.2, 0.45)
			crust = 0.15
		MDSLava.Liquid.CURSED:
			crust_color = Color(0.10, 0.04, 0.16)
			hot_color = Color(0.55, 0.18, 0.85)
			bright_color = Color(0.92, 0.65, 1.0)
			glow_color = Color(0.6, 0.25, 1.0, 0.45)
			crust = 0.35

func _affect(body: Node2D, delta: float, strength: float) -> void:
	if push_down > 0.0:
		push_body(body, global_transform.basis_xform(Vector2.DOWN).normalized() * push_down * strength, delta)
	if damage > 0.0:
		hurt_body(body, damage * strength, damage_interval)
