@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/environment/steam_vent.svg")
class_name MDSSteamVent
extends MDSEnvironmentEffect
## A vent forcing out hot steam under pressure: thin wisps curl out of it, its mouth glows as a
## warning, then a jet blasts out (white-hot at the vent, cooling to a dark red crest, with
## glitter thrown up along it), holds, and dies away. Bodies of [member affect_groups] caught in
## the jet are thrown along it ([member launch_speed]) and scalded ([member damage]).
##
## The node stands on the vent and the jet rises from it: [member size] is the jet's width and
## length. Rotate the node to point it another way (sideways out of a wall, down from a
## ceiling). Rows of vents take turns with [member phase_offset].

## Emitted when the jet blasts out.
signal erupted
## Emitted when the jet has died away.
signal calmed

## - [code]REPEAT[/code]: erupts every [member rest_time] seconds.
## - [code]CONSTANT[/code]: always blasting.
## - [code]ON_DEMAND[/code]: rests until [method erupt] is called (a switch, a boss).
enum Cycle { REPEAT, CONSTANT, ON_DEMAND }
enum Phase { REST, WARN, RISE, BLAST, FADE }

## Seconds the jet takes to shoot out to full length, and to die away.
const RISE_TIME := 0.2
const FADE_TIME := 0.45
## The billows are sized for a jet this long; others are scaled to match.
const DESIGN_LENGTH := 540.0

@export var cycle: Cycle = Cycle.REPEAT
## Seconds between eruptions (REPEAT).
@export_range(0.0, 60.0, 0.05) var rest_time := 2.5
## Seconds the mouth glows before the jet blasts out.
@export_range(0.0, 10.0, 0.05) var warning_time := 0.6
## Seconds the jet blasts at full length.
@export_range(0.05, 30.0, 0.05) var blast_time := 1.2
## Seconds before the first eruption (vents in a row can take turns).
@export_range(0.0, 60.0, 0.05) var phase_offset := 0.0
@export_group("Look")
@export var vent_color := Color(1.0, 0.95, 0.88):
	set(v):
		vent_color = v
		_changed()
@export var hot_color := Color(1.0, 0.47, 0.36):
	set(v):
		hot_color = v
		_changed()
@export var crest_color := Color(0.64, 0.12, 0.11):
	set(v):
		crest_color = v
		_changed()
@export var sparkle_color := Color(1.0, 0.74, 0.84):
	set(v):
		sparkle_color = v
		_changed()
## Glitter thrown up along the jet.
@export_range(0.0, 1.0) var sparkles := 0.6:
	set(v):
		sparkles = v
		_changed()
## How fast the billows climb.
@export_range(0.2, 6.0) var rise_speed := 1.6:
	set(v):
		rise_speed = v
		_changed()
## Thin wisps out of the vent between eruptions.
@export var idle_wisps := true
@export_group("Force")
## How fast (px/s) the jet throws bodies along it. 0: it doesn't.
@export_range(0.0, 4000.0) var launch_speed := 900.0
## Damage dealt once per eruption to each body caught in it. 0: none.
@export var damage := 0.0
## Share of the jet's width that throws and scalds (grazing its billows is free).
@export_range(0.1, 1.0) var core_width := 0.6

var phase: Phase = Phase.REST
var _t := 0.0
var _first := true
var _scalded: Dictionary = {}
var _progress := 0.0
var _jet_fade := 1.0
var _glow := 0.0
var _wisps := 0.0

func _init() -> void:
	z_index = 6
	size = Vector2(80, 520)

func get_effect_id() -> String:
	return "steam_vent"

## The jet: [member size] wide and long, rising from the node's position.
func get_effect_rect() -> Rect2:
	return Rect2(Vector2(-size.x * 0.5, -size.y), size)

## The part of the jet that throws and scalds: its core, as far as it has reached.
func get_body_rect() -> Rect2:
	var w := size.x * core_width
	var h := size.y * _progress
	return Rect2(Vector2(-w * 0.5, -h), Vector2(w, h))

func _build() -> void:
	# Wider than the jet, so its billows have room.
	add_quad(shader("steam_vent"), Rect2(Vector2(-size.x * 0.95, -size.y), Vector2(size.x * 1.9, size.y)))

func _update_params() -> void:
	set_param(&"vent_color", vent_color)
	set_param(&"hot_color", hot_color)
	set_param(&"crest_color", crest_color)
	set_param(&"sparkle_color", sparkle_color)
	set_param(&"sparkles", sparkles)
	set_param(&"rise_speed", rise_speed)
	set_param(&"stretch", size.y / DESIGN_LENGTH)
	_send_cycle()

func _send_cycle() -> void:
	set_param(&"progress", _progress)
	set_param(&"fade", _jet_fade)
	set_param(&"glow", _glow)
	set_param(&"wisps", _wisps)

## Starts an eruption now (with its warning first). Returns false while one is under way.
func erupt() -> bool:
	if phase != Phase.REST:
		return false
	_set_phase(Phase.WARN if warning_time > 0.0 else Phase.RISE)
	return true

## Whether the jet is out (throwing and scalding).
func is_blasting() -> bool:
	return cycle == Cycle.CONSTANT or phase == Phase.BLAST or (phase == Phase.RISE and _t >= RISE_TIME * 0.6)

func _set_phase(p: Phase) -> void:
	phase = p
	_t = 0.0
	if p == Phase.RISE:
		_scalded.clear()
		erupted.emit()
	elif p == Phase.REST:
		calmed.emit()

func _tick(delta: float) -> void:
	_t += delta
	if cycle == Cycle.CONSTANT:
		_progress = 1.0
		_jet_fade = 1.0
		_glow = 0.0
		_wisps = 0.0
		_send_cycle()
		return
	match phase:
		Phase.REST:
			_progress = 0.0
			_jet_fade = 1.0
			_glow = 0.0
			_wisps = 1.0 if idle_wisps else 0.0
			var wait := rest_time + (phase_offset if _first else 0.0)
			if cycle == Cycle.REPEAT and _t >= wait:
				_first = false
				erupt()
		Phase.WARN:
			_glow = clampf(_t / maxf(warning_time, 0.01), 0.0, 1.0)
			if _t >= warning_time:
				_set_phase(Phase.RISE)
		Phase.RISE:
			_glow = 0.0
			_wisps = 0.0
			_progress = ease(clampf(_t / RISE_TIME, 0.0, 1.0), 0.4)
			if _t >= RISE_TIME:
				_progress = 1.0
				_set_phase(Phase.BLAST)
		Phase.BLAST:
			if _t >= blast_time:
				_set_phase(Phase.FADE)
		Phase.FADE:
			_jet_fade = clampf(1.0 - _t / FADE_TIME, 0.0, 1.0)
			if _t >= FADE_TIME:
				_progress = 0.0
				_jet_fade = 1.0
				_set_phase(Phase.REST)
	_send_cycle()

func _affect(body: Node2D, _delta: float, strength: float) -> void:
	if not is_blasting():
		return
	var up := global_transform.basis_xform(Vector2.UP).normalized()
	if launch_speed > 0.0:
		launch_body(body, up * launch_speed * strength)
	if damage > 0.0 and not _scalded.has(body.get_instance_id()):
		_scalded[body.get_instance_id()] = true
		hurt_body(body, damage * strength, 0.0)
