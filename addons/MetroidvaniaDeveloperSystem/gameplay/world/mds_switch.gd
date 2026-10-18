@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_switch.svg")
class_name MDSSwitch
extends Area2D
## A lever, a pressure plate or a crystal to strike: it sets the story flag [member flag]
## ([method MDSGameplay.set_flag]), so barriers and gates that require [code]flag:<name>[/code] open,
## objectives complete and dialogue changes. [member trigger]: hit it with an attack (HIT), interact
## at it (INTERACT) or step on it (STEP). [member mode]: ONE_SHOT stays on (kept by the flag, also
## after a save and load), TOGGLE flips it on and off, TIMED turns it off again after
## [member time] seconds.
##
## It writes [code]mds_grants = ["flag:<name>"][/code] metadata, so the analysis treats it as
## granting the flag.

signal switched(on: bool)

enum Mode { ONE_SHOT, TOGGLE, TIMED }
enum Trigger { HIT, INTERACT, STEP }

@export var flag := "":
	set(v):
		flag = v
		_update_meta()
@export var mode: Mode = Mode.ONE_SHOT
@export var time := 5.0
@export var trigger: Trigger = Trigger.HIT:
	set(v):
		trigger = v
		queue_redraw()
## Shown over it while the player can interact (INTERACT).
@export var prompt := "Pull"
@export var size := Vector2(40, 48):
	set(v):
		size = v
		queue_redraw()
@export var on_color := Color(0.5, 1.0, 0.6)
@export var off_color := Color(0.85, 0.5, 0.35)

var is_on := false
var _left := 0.0
var _inside := false
var _label: Label

func _ready() -> void:
	_update_meta()
	if Engine.is_editor_hint():
		return
	collision_layer = MDSGameplaySetup.bit("interact")
	collision_mask = MDSGameplaySetup.player_detect_mask()
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = size
		cs.shape = r
		add_child(cs)
	if trigger == Trigger.HIT:
		var hb := MDSHurtbox.make(MDSHurtbox.Team.NEUTRAL, size + Vector2(8, 8))
		hb.name = "Hurtbox"
		add_child(hb)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var kit := MDSGameplay.find_from(self)
	if kit and mode != Mode.TIMED:
		is_on = MDSGameplay.truthy(kit.get_flag(flag))
		kit.flag_changed.connect(func(f: String, v: Variant) -> void:
			if f == MDSGameplay.normalize_id(flag):
				is_on = MDSGameplay.truthy(v)
				queue_redraw())
	queue_redraw()

func _update_meta() -> void:
	if flag.strip_edges().is_empty():
		if has_meta(&"mds_grants"):
			remove_meta(&"mds_grants")
	else:
		set_meta(&"mds_grants", PackedStringArray(["flag:" + MDSGameplay.normalize_id(flag)]))

## Flips it as its mode says.
func activate() -> void:
	match mode:
		Mode.ONE_SHOT:
			if is_on:
				return
			_switch_to(true)
		Mode.TOGGLE:
			_switch_to(not is_on)
		Mode.TIMED:
			_left = time
			if not is_on:
				_switch_to(true)

func _switch_to(on: bool) -> void:
	is_on = on
	var kit := MDSGameplay.find_from(self)
	if kit and not flag.is_empty():
		kit.set_flag(flag, on)
	switched.emit(on)
	queue_redraw()

## An attack hit it (HIT): it flips.
func mds_take_hit(_info: MDSDamageInfo) -> int:
	if trigger != Trigger.HIT:
		return 0
	activate()
	return 1

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return
	_inside = true
	if trigger == Trigger.STEP:
		activate()
	elif trigger == Trigger.INTERACT:
		_show_prompt(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group(&"player"):
		_inside = false
		_show_prompt(false)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or trigger != Trigger.INTERACT or not _inside:
		return
	if InputMap.has_action(&"interact") and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		activate()

func _show_prompt(on: bool) -> void:
	if prompt.is_empty():
		return
	if on and not _label:
		_label = Label.new()
		_label.text = prompt
		_label.add_theme_constant_override(&"outline_size", 5)
		_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		_label.position = Vector2(-40, -size.y - 30)
		add_child(_label)
	if _label:
		_label.visible = on

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or mode != Mode.TIMED or not is_on:
		return
	_left -= delta
	if _left <= 0.0:
		_switch_to(false)

func _draw() -> void:
	var c := on_color if is_on else off_color
	match trigger:
		Trigger.STEP:
			var plate := Rect2(-size.x * 0.5, size.y * 0.5 - (6.0 if is_on else 12.0), size.x, 12.0 if not is_on else 6.0)
			draw_rect(Rect2(-size.x * 0.6, size.y * 0.5 - 4, size.x * 1.2, 4), Color(0.25, 0.22, 0.2))
			draw_rect(plate, c)
		Trigger.HIT:
			var pts := PackedVector2Array([Vector2(0, -size.y * 0.5), Vector2(size.x * 0.4, 0), Vector2(0, size.y * 0.5), Vector2(-size.x * 0.4, 0)])
			draw_colored_polygon(pts, c)
			draw_circle(Vector2.ZERO, size.x * 0.15, Color(1, 1, 1, 0.8))
		_:
			draw_rect(Rect2(-size.x * 0.3, size.y * 0.25, size.x * 0.6, size.y * 0.25), Color(0.3, 0.26, 0.22))
			var tip := Vector2(size.x * (0.35 if is_on else -0.35), -size.y * 0.35)
			draw_line(Vector2(0, size.y * 0.3), tip, Color(0.6, 0.55, 0.5), 4.0)
			draw_circle(tip, 6.0, c)
