@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSGateBarrier
extends StaticBody2D
## A physical gate that stays shut until a condition is met, then opens visibly and stays
## open (also after saving and loading). Put it in a doorway, next to (or under) the
## [MDSGate] it guards.
##
## The condition is the gate's requirements on the map ([member gate]'s [code]requires[/code])
## or [member requires]: abilities, keys ([method MDSWorldGame.grant_ability]) and stored
## objects ([code]object:<id>[/code]) are one mechanism, so a key is just an ability or a
## stored object.
##
## It needs a collision shape child. Its look is its other children (sprites...), which slide
## up and fade as it opens, or an AnimationPlayer child with an "open" animation; with neither
## it draws a plain bar of its collision's size.

## Emitted when it opens (not when it starts open after a load).
signal opened

## The gate it guards: its map requirements are the condition. Empty: a parent MDSGate.
@export var gate: MDSGate
## Requirements instead of the gate's: ability names, "object:<id>" or "boss:<name>".
@export var requires: PackedStringArray = []
## Seconds the opening takes.
@export var open_time := 0.6
## How far (px) the look slides up as it opens (0: its collision's height).
@export var lift := 0.0
## Colour of the bar drawn when it has no look of its own.
@export var bar_color := Color(0.35, 0.3, 0.26)

var is_open := false
var _game: MDSWorldGame

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_game = MDSWorldGame.instance
	if not gate and get_parent() is MDSGate:
		gate = get_parent()
	if _game:
		_game.ability_gained.connect(func(_a: String) -> void: _check())
		_game.room_loaded.connect(func(_r: String) -> void: _check())
		if _game.is_object_stored(_id()):
			_set_open(true, false)
			return
	_check.call_deferred()

## The requirements that keep it shut.
func get_requirements() -> PackedStringArray:
	if not requires.is_empty():
		return requires
	if gate and gate.get_world():
		return PackedStringArray(gate.get_world().get_gate(gate.get_room_id(), gate.get_gate_name()).get("requires", []))
	return PackedStringArray()

## Whether every requirement is met.
func is_unlocked() -> bool:
	if not _game:
		return false
	for r in get_requirements():
		if not _game.is_condition_met(r):
			return false
	return true

func _id() -> String:
	return _game.object_id(self) if _game else String(name)

func _check() -> void:
	if not is_open and is_unlocked():
		open()

## Opens it now (animated) and remembers it.
func open() -> void:
	if is_open:
		return
	if _game:
		_game.store_object(_id())
	_set_open(true, true)
	opened.emit()

func _set_open(on: bool, animate: bool) -> void:
	is_open = on
	# No collision once open (deferred: it may open during a physics callback).
	for c in get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			c.set_deferred(&"disabled", on)
	var anim := _animation_player()
	if anim and anim.has_animation(&"open"):
		anim.play(&"open")
		if not animate:
			anim.seek(anim.current_animation_length, true)
		return
	var h := lift if lift > 0.0 else _shape_rect().size.y
	if not animate:
		modulate.a = 0.0 if on else 1.0
		visible = not on
		return
	var tw := create_tween().set_parallel()
	for c in get_children():
		if c is Node2D and not (c is CollisionShape2D or c is CollisionPolygon2D):
			tw.tween_property(c, "position:y", (c as Node2D).position.y - h, open_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, open_time)
	tw.chain().tween_callback(func() -> void: visible = false)

func _animation_player() -> AnimationPlayer:
	for c in get_children():
		if c is AnimationPlayer:
			return c
	return null

func _shape_rect() -> Rect2:
	for c in get_children():
		if c is CollisionShape2D and c.shape:
			var r: Rect2 = c.shape.get_rect()
			return Rect2(r.position + (c as Node2D).position, r.size)
	return Rect2(-16, -64, 32, 128)

func _has_look() -> bool:
	for c in get_children():
		if c is CanvasItem and not (c is CollisionShape2D or c is CollisionPolygon2D):
			return true
	return false

func _draw() -> void:
	if _has_look():
		return
	var r := _shape_rect()
	draw_rect(r, bar_color)
	for i in range(1, 4):
		var x := lerpf(r.position.x, r.end.x, i / 4.0)
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), bar_color.darkened(0.4), 2.0)
	draw_rect(r, bar_color.darkened(0.6), false, 2.0)
