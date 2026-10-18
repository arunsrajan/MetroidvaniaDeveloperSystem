@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_player_visual.svg")
class_name MDSPlayerVisual
extends Node2D
## The player's placeholder look: a small cloaked figure drawn in code (no art needed), facing the
## way it moves, squashed when crouching or sliding, stretched when dashing, leaning on walls. Swap
## it for an AnimatedSprite2D named "Visual" (animations named after the states: idle, run, jump,
## fall, dash...) and [MDSPlayer] plays those instead.

@export var size := Vector2(28, 60)
@export var cloak_color := Color(0.18, 0.2, 0.28)
@export var body_color := Color(0.92, 0.9, 0.86)
@export var trim_color := Color(0.85, 0.3, 0.3)

var _state: StringName = &"Idle"
var _facing := 1
var _velocity := Vector2.ZERO
var _height := 1.0

## Called by the player every physics frame.
func set_pose(state: StringName, facing: int, velocity: Vector2, height_share: float) -> void:
	if state == _state and facing == _facing and is_equal_approx(height_share, _height) and velocity.distance_squared_to(_velocity) < 400.0:
		return
	_state = state
	_facing = facing
	_velocity = velocity
	_height = height_share
	queue_redraw()

func play(_animation: StringName) -> void:
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y * _height
	var feet := size.y * 0.5
	var stretch := 1.0
	if _state in [&"Dash", &"AirDash"]:
		stretch = 1.35
	var bw := w * stretch
	var lean := 0.0
	if _state == &"WallSlide":
		lean = -4.0 * _facing
	var top := feet - h
	# Cloak.
	var cloak := PackedVector2Array([
		Vector2(-bw * 0.5 + lean, feet), Vector2(bw * 0.5 + lean, feet),
		Vector2(bw * 0.42, top + h * 0.38), Vector2(-bw * 0.42, top + h * 0.38)])
	draw_colored_polygon(cloak, cloak_color)
	draw_line(Vector2(-bw * 0.5 + lean, feet - 2), Vector2(bw * 0.5 + lean, feet - 2), trim_color, 2.0)
	# Head.
	var head_r := minf(w * 0.42, h * 0.24)
	var head := Vector2(_facing * 2.0, top + head_r + 1.0)
	draw_circle(head, head_r, body_color)
	# Horns.
	draw_line(head + Vector2(-head_r * 0.5, -head_r * 0.7), head + Vector2(-head_r * 0.8, -head_r * 1.6), body_color, 2.5)
	draw_line(head + Vector2(head_r * 0.5, -head_r * 0.7), head + Vector2(head_r * 0.8, -head_r * 1.6), body_color, 2.5)
	# Eyes, toward where it faces.
	var eye := head + Vector2(_facing * head_r * 0.35, 0)
	draw_circle(eye + Vector2(-3, 0), 2.2, Color(0.05, 0.05, 0.08))
	draw_circle(eye + Vector2(3, 0), 2.2, Color(0.05, 0.05, 0.08))
	if _state == &"Hurt":
		draw_arc(Vector2(0, (top + feet) * 0.5), w * 0.9, 0, TAU, 20, Color(1, 0.4, 0.3, 0.6), 2.0)
	elif _state == &"Glide":
		draw_line(Vector2(-w * 1.1, top + h * 0.35), Vector2(w * 1.1, top + h * 0.35), cloak_color.lightened(0.3), 4.0)
