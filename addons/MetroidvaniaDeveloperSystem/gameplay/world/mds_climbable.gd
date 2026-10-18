@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_climbable.svg")
class_name MDSClimbable
extends Area2D
## A ladder or vines: with the [code]climb[/code] ability, up or down while in it climbs. A
## marker of [member size] (centred on the node); nothing is saved.

enum Look { LADDER, VINES }

@export var size := Vector2(40, 240):
	set(v):
		size = v.max(Vector2(8, 8))
		_fit()
		queue_redraw()
@export var look: Look = Look.VINES:
	set(v):
		look = v
		queue_redraw()
@export var color := Color(0.35, 0.6, 0.3)

func _ready() -> void:
	_fit()
	if Engine.is_editor_hint():
		return
	collision_layer = MDSGameplaySetup.bit("interact")
	collision_mask = MDSGameplaySetup.player_detect_mask()
	body_entered.connect(func(b: Node) -> void:
		if b is MDSPlayer and not (b as MDSPlayer).climbables.has(self):
			(b as MDSPlayer).climbables.append(self))
	body_exited.connect(func(b: Node) -> void:
		if b is MDSPlayer:
			(b as MDSPlayer).climbables.erase(self))

func _fit() -> void:
	var cs := get_node_or_null(^"Shape") as CollisionShape2D
	if not cs:
		if not is_inside_tree():
			return
		cs = CollisionShape2D.new()
		cs.name = "Shape"
		add_child(cs)
	if not cs.shape is RectangleShape2D:
		cs.shape = RectangleShape2D.new()
	(cs.shape as RectangleShape2D).size = size

func _draw() -> void:
	var r := Rect2(-size * 0.5, size)
	if look == Look.LADDER:
		var wood := Color(0.55, 0.4, 0.25)
		draw_line(r.position, Vector2(r.position.x, r.end.y), wood, 4.0)
		draw_line(Vector2(r.end.x, r.position.y), r.end, wood, 4.0)
		var y := r.position.y + 12.0
		while y < r.end.y:
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), wood, 3.0)
			y += 24.0
		return
	for k in 3:
		var x := r.position.x + size.x * (0.2 + 0.3 * k)
		var pts := PackedVector2Array()
		var y := r.position.y
		while y <= r.end.y:
			pts.append(Vector2(x + sin(y * 0.05 + k) * 5.0, y))
			y += 8.0
		draw_polyline(pts, color, 3.0)
		for i in range(0, pts.size(), 3):
			draw_circle(pts[i] + Vector2(4, 0), 4.0, color.lightened(0.2))
