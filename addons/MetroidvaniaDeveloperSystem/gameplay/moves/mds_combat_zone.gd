@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_hitbox.svg")
class_name MDSCombatZone
extends MDSHitbox
## A place that warns, then hurts: drawn faintly for [member telegraph] seconds, then its hit is on
## for [member active_time]. Left by [MDSMoveZones], and by a [MDSBossShot] when it goes off. With
## [member hits_to_break] the player can cut it down. With no [member attack] it is only a mark.

enum Shape { CIRCLE, BOX }

@export var shape: Shape = Shape.CIRCLE
## CIRCLE: x is the diameter.
@export var size := Vector2(120, 120)
@export var telegraph := 0.7
@export var active_time := 0.25
## Hits it takes to break (0: it can't be hit).
@export var hits_to_break := 0
## It goes when the enemy that left it is staggered or dies.
@export var clear_on_stagger := true
@export var color := Color(1.0, 0.75, 0.35)
## A BOX hangs from here: its top edge is where it was put.
@export var anchor_top := false
## A BOX stands here: its bottom edge is where it was put.
@export var anchor_bottom := false
## Shakes the camera when it goes off (pixels).
@export var shake := 0.0

var _age := 0.0
var _hits_taken := 0
var _on := false
var _guard: MDSHurtbox

func _init() -> void:
	super()
	active = false
	one_hit_per_target = true

## A harmless mark at [param at].
static func marker(at: Vector2, p_size: Vector2, seconds: float, p_color: Color) -> MDSCombatZone:
	var z := MDSCombatZone.new()
	z.shape = Shape.BOX
	z.size = p_size
	z.telegraph = seconds
	z.active_time = 0.01
	z.color = p_color
	z.position = at
	z.mark_only = true
	return z

## It only warns, whatever its attack.
var mark_only := false

func _ready() -> void:
	super()
	top_level = true
	monitoring = false
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	if shape == Shape.CIRCLE:
		var c := CircleShape2D.new()
		c.radius = size.x * 0.5
		cs.shape = c
	else:
		var r := RectangleShape2D.new()
		r.size = size
		cs.shape = r
		cs.position = _box_center()
	add_child(cs)
	if hits_to_break > 0:
		_guard = MDSHurtbox.make(MDSHurtbox.Team.NEUTRAL, size)
		_guard.name = "Guard"
		_guard.position = _box_center()
		add_child(_guard)
	queue_redraw()

func _box_center() -> Vector2:
	if anchor_top:
		return Vector2(0, size.y * 0.5)
	if anchor_bottom:
		return Vector2(0, -size.y * 0.5)
	return Vector2.ZERO

## The player hits it (its hurtbox hands the hit here).
func mds_take_hit(_info: MDSDamageInfo) -> int:
	if hits_to_break <= 0:
		return 0
	_hits_taken += 1
	if _hits_taken >= hits_to_break:
		queue_free()
	return 1

func _physics_process(delta: float) -> void:
	_age += delta
	if not _on and _age >= telegraph:
		_on = true
		if mark_only:
			queue_free()
			return
		active = true
		monitoring = true
		if shake > 0.0 and is_instance_valid(source):
			var game := MDSWorldGame.instance
			if game and game.room_camera and game.room_camera.has_method(&"shake"):
				game.room_camera.call(&"shake", shake, 0.2)
		queue_redraw()
	if _on and _age >= telegraph + active_time:
		queue_free()
		return
	super(delta)
	if not _on:
		queue_redraw()

func _draw() -> void:
	var share := clampf(_age / maxf(0.01, telegraph), 0.0, 1.0)
	var fill := Color(color, 0.85) if _on else Color(color, 0.08 + 0.22 * share)
	var line := Color(color, 0.95 if _on else 0.35 + 0.5 * share)
	if shape == Shape.CIRCLE:
		draw_circle(Vector2.ZERO, size.x * 0.5 * (1.0 if _on else share), fill)
		draw_arc(Vector2.ZERO, size.x * 0.5, 0.0, TAU, 32, line, 2.0)
	else:
		var r := Rect2(_box_center() - size * 0.5, size)
		draw_rect(r, fill)
		draw_rect(r, line, false, 2.0)
