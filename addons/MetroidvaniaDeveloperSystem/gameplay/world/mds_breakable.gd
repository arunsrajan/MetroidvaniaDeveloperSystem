@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_breakable.svg")
class_name MDSBreakable
extends StaticBody2D
## A wall, floor or block that breaks: solid terrain (layer 1) with an [MDSHurtbox]. Only attacks
## whose [member MDSAttackData.breaks] list its [member kind] damage it ([code]wall[/code]: any
## attack; [code]cracked_floor[/code]: a ground pound; [code]reinforced[/code]: the super attack;
## any name of your own), and only once [member requires] is met. After [member hits] such hits it
## breaks and stays broken ([method MDSWorldGame.store_object]: gone when its room loads again, and
## after a save and load). A secret wall is a [code]wall[/code] with no requirement.
##
## It writes [member requires] as [code]mds_requires[/code] metadata, so the scanner ties it to the
## nearest exit and the Progress tab knows what opens it. Its look is a block of [member size]
## drawn with cracks (its other children, when it has any, are its look instead).

signal broken
## A hit landed but it didn't break yet ([param left]: hits to go).
signal damaged(left: int)
## A hit that can't break it (wrong kind, or its requirement unmet).
signal deflected(info: MDSDamageInfo)

@export var kind := "wall":
	set(v):
		kind = v
		queue_redraw()
@export var hits := 1
@export var requires: PackedStringArray = []:
	set(v):
		requires = v
		_update_meta()
@export var break_effect: PackedScene
## The block's size (px), centred on the node.
@export var size := Vector2(64, 128):
	set(v):
		size = v.max(Vector2(8, 8))
		_fit_shapes()
		queue_redraw()
@export var color := Color(0.42, 0.37, 0.32)

var hits_left := 1
var _shake := 0.0

func _init() -> void:
	add_to_group(&"breakable")

func _ready() -> void:
	_update_meta()
	_fit_shapes()
	if Engine.is_editor_hint():
		return
	hits_left = maxi(1, hits)
	collision_layer = MDSGameplaySetup.bit("world")
	var game := MDSWorldGame.instance
	if game and game.is_object_stored(self):
		queue_free()

func _update_meta() -> void:
	if requires.is_empty():
		if has_meta(&"mds_requires"):
			remove_meta(&"mds_requires")
	else:
		set_meta(&"mds_requires", requires.duplicate())

## Its collision and its hurtbox (made when missing) cover [member size].
func _fit_shapes() -> void:
	# Not while the scene is being loaded (its own Shape child isn't there yet).
	if not is_inside_tree():
		return
	var cs := get_node_or_null(^"Shape") as CollisionShape2D
	if not cs:
		cs = CollisionShape2D.new()
		cs.name = "Shape"
		add_child(cs)
	if not cs.shape is RectangleShape2D:
		cs.shape = RectangleShape2D.new()
	(cs.shape as RectangleShape2D).size = size
	if Engine.is_editor_hint():
		return
	var hb := get_node_or_null(^"Hurtbox") as MDSHurtbox
	if not hb:
		hb = MDSHurtbox.make(MDSHurtbox.Team.NEUTRAL, size + Vector2(12, 12))
		hb.name = "Hurtbox"
		add_child(hb)

## Whether [param info] can damage it: it lists its kind, and the requirement is met.
func can_break_with(info: MDSDamageInfo) -> bool:
	if not info.breaks.has(kind):
		return false
	if requires.is_empty():
		return true
	var game := MDSWorldGame.instance
	if not game:
		return false
	for r in requires:
		if not game.is_condition_met(r):
			return false
	return true

## A hit from its hurtbox: damages it when it can (returns 1), else deflects (0).
func mds_take_hit(info: MDSDamageInfo) -> int:
	if is_queued_for_deletion():
		return 0
	if not can_break_with(info):
		deflected.emit(info)
		_shake = 0.15
		return 0
	hits_left -= 1
	_shake = 0.2
	queue_redraw()
	if hits_left <= 0:
		break_now()
	else:
		damaged.emit(hits_left)
	return 1

## Breaks it now and remembers it.
func break_now() -> void:
	var game := MDSWorldGame.instance
	if game:
		game.store_object(self)
	if break_effect and get_parent():
		var fx := break_effect.instantiate()
		get_parent().add_child(fx)
		if fx is Node2D:
			(fx as Node2D).global_position = global_position
	else:
		_debris()
	broken.emit()
	queue_free()

## A burst of chips where it stood.
func _debris() -> void:
	if not get_parent():
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.8
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = size * 0.5
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 900)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color = color.lightened(0.15)
	get_parent().add_child(p)
	p.global_position = global_position
	p.emitting = true
	p.finished.connect(p.queue_free)

func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		queue_redraw()

func _has_look() -> bool:
	for c in get_children():
		if c is CanvasItem and not c is CollisionShape2D and not c is MDSHurtbox:
			return true
	return false

func _draw() -> void:
	if _has_look():
		return
	var off := Vector2(randf_range(-2, 2), 0) if _shake > 0.0 else Vector2.ZERO
	var r := Rect2(-size * 0.5 + off, size)
	var base := color
	if kind == "reinforced":
		base = color.darkened(0.25)
	draw_rect(r, base)
	draw_rect(r, base.darkened(0.45), false, 2.0)
	# Bricks.
	var rows := maxi(1, int(size.y / 32.0))
	for i in range(1, rows):
		var y := r.position.y + size.y * i / rows
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), base.darkened(0.3), 1.5)
	# Cracks: more as it takes hits.
	var crack := base.darkened(0.6)
	var damage_share := 1.0 - float(hits_left) / maxf(1.0, hits)
	draw_polyline(PackedVector2Array([r.get_center() + Vector2(-size.x * 0.3, -size.y * 0.3), r.get_center() + Vector2(-2, -4), r.get_center() + Vector2(size.x * 0.25, size.y * 0.1), r.get_center() + Vector2(size.x * 0.05, size.y * 0.35)]), crack, 2.0)
	if damage_share > 0.0 or kind == "cracked_floor":
		draw_polyline(PackedVector2Array([r.get_center() + Vector2(size.x * 0.3, -size.y * 0.35), r.get_center() + Vector2(4, 2), r.get_center() + Vector2(-size.x * 0.3, size.y * 0.3)]), crack, 2.0)
	if kind == "reinforced":
		for x in [0.25, 0.75]:
			draw_line(Vector2(r.position.x + size.x * x, r.position.y), Vector2(r.position.x + size.x * x, r.end.y), Color(0.55, 0.58, 0.62), 4.0)
