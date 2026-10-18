@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_arena_door.svg")
class_name MDSArenaDoor
extends StaticBody2D
## A door of a boss arena ([MDSBossArena]): open (no collision, its bars up) until the fight starts,
## shut during it, open again after. [member size] is centred on the node.

signal shut
signal opened

@export var size := Vector2(40, 180):
	set(v):
		size = v.max(Vector2(8, 8))
		queue_redraw()
@export var color := Color(0.35, 0.3, 0.32)
@export var close_time := 0.35

var is_closed := false
var _down := 0.0 ## 0 open .. 1 shut, for the look

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	collision_layer = MDSGameplaySetup.bit("world")
	var cs := get_node_or_null(^"Shape") as CollisionShape2D
	if not cs:
		cs = CollisionShape2D.new()
		cs.name = "Shape"
		var r := RectangleShape2D.new()
		r.size = size
		cs.shape = r
		add_child(cs)
	cs.disabled = true

func close() -> void:
	_set_closed(true)

func open() -> void:
	_set_closed(false)

func _set_closed(on: bool) -> void:
	if on == is_closed:
		return
	is_closed = on
	for c in get_children():
		if c is CollisionShape2D:
			c.set_deferred(&"disabled", not on)
	var tw := create_tween()
	tw.tween_property(self, "_down", 1.0 if on else 0.0, close_time)
	tw.tween_callback(queue_redraw)
	if on:
		shut.emit()
	else:
		opened.emit()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	var r := Rect2(-size * 0.5, size)
	var shown := 1.0 if Engine.is_editor_hint() else _down
	var h := size.y * shown
	var n := maxi(2, int(size.x / 12.0))
	for i in n:
		var x := r.position.x + size.x * (i + 0.5) / n
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + h), color, 5.0)
	draw_line(Vector2(r.position.x, r.position.y + h), Vector2(r.end.x, r.position.y + h), color.darkened(0.3), 6.0)
	if Engine.is_editor_hint():
		draw_rect(r, Color(color, 0.25), false, 1.0)
