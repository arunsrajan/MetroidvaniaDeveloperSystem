@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_checkpoint.svg")
class_name MDSCheckpoint
extends Area2D
## A checkpoint in a room of hazards: touched, it is where spikes and pits ([MDSHazard] RESPAWN,
## lava) send the player back to, in this room, instead of the last safe ground. It is not a save
## point (benches are) and nothing is saved.

signal reached

@export var size := Vector2(48, 96):
	set(v):
		size = v.max(Vector2(8, 8))
		queue_redraw()
## Where the player is put back, from the node (its feet): up by about half the player's height.
@export var respawn_offset := Vector2(0, -32)
@export var color := Color(0.55, 0.85, 1.0)

var active := false

func _init() -> void:
	add_to_group(&"mds_stands")

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	collision_layer = 0
	collision_mask = MDSGameplaySetup.player_detect_mask()
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = size
		cs.shape = r
		cs.position = Vector2(0, -size.y * 0.5)
		add_child(cs)
	body_entered.connect(func(b: Node) -> void:
		if b is MDSPlayer:
			(b as MDSPlayer).set_checkpoint(global_position + respawn_offset)
			if not active:
				active = true
				queue_redraw()
				reached.emit())

func _draw() -> void:
	var c := color if active else Color(color, 0.4)
	draw_line(Vector2.ZERO, Vector2(0, -size.y), Color(0.45, 0.42, 0.4), 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -size.y), Vector2(size.x * 0.5, -size.y * 0.82), Vector2(0, -size.y * 0.64)]), c)
	if active:
		draw_circle(Vector2(0, -size.y), 10.0, Color(c, 0.3))
