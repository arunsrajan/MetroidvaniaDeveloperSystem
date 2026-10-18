@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_grapple_point.svg")
class_name MDSGrapplePoint
extends Node2D
## A ring the player's grapple hooks ([code]grapple[/code] ability): the nearest one in reach and
## in sight when grapple is pressed pulls the player to it. A marker: nothing is saved.

@export var enabled := true:
	set(v):
		enabled = v
		queue_redraw()
@export var radius := 14.0
@export var color := Color(0.75, 0.9, 1.0)

func _init() -> void:
	add_to_group(&"mds_grapple_point")

func _draw() -> void:
	var c := color if enabled else Color(color, 0.3)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 24, c, 3.0)
	draw_circle(Vector2.ZERO, radius * 0.35, c)
	draw_line(Vector2(0, -radius), Vector2(0, -radius - 18), Color(c, 0.6), 2.0)
