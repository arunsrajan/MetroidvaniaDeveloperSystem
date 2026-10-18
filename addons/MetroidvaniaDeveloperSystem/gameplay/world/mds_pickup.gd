@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_pickup.svg")
class_name MDSPickup
extends Area2D
## An item to pick up: a key, a consumable, a charm, a collectible ([member item], [member amount]).
## Touching it (or interact at it, without [member auto_collect]) adds it ([method MDSGameplay.add_item]).
## A [member persistent] one is gone for good once taken ([method MDSWorldGame.store_object]); drops
## from enemies are not persistent. With [member magnet_radius] it flies to a player that comes near.
##
## It writes [code]mds_grants = ["item:<id>"][/code] metadata, so the Progress tab knows where each
## key is found, and it is in the [code]pickup[/code] group. Subtypes: [MDSHealthUpgrade],
## [MDSManaUpgrade], [MDSSlotUpgrade], [MDSCurrencyPickup].

signal collected(id: String, amount: int)

@export var item: MDSItemData:
	set(v):
		item = v
		_update_meta()
		queue_redraw()
@export var amount := 1
@export var persistent := true:
	set(v):
		persistent = v
		_update_meta()
@export var auto_collect := true
## A player this close (px) pulls it in (0: never).
@export var magnet_radius := 0.0
@export var magnet_speed := 520.0
@export var radius := 16.0
@export var color := Color(0.95, 0.8, 0.4)

var _time := 0.0
var _inside := false

func _init() -> void:
	add_to_group(&"pickup")

func _ready() -> void:
	_update_meta()
	if Engine.is_editor_hint():
		return
	collision_layer = MDSGameplaySetup.bit("interact")
	collision_mask = MDSGameplaySetup.player_detect_mask()
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = radius
		cs.shape = c
		add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(func(b: Node) -> void:
		if b.is_in_group(&"player"):
			_inside = false)
	var game := MDSWorldGame.instance
	if persistent and game and game.is_object_stored(self):
		queue_free()

## The id it adds (the item's).
func get_item_id() -> String:
	return MDSGameplay.normalize_id(item.id) if item else ""

## What it grants, for the analysis ("item:red_key").
func get_grant() -> String:
	var id := get_item_id()
	return "item:" + id if not id.is_empty() else ""

func _update_meta() -> void:
	var g := get_grant()
	if g.is_empty() or not persistent:
		if has_meta(&"mds_grants"):
			remove_meta(&"mds_grants")
	else:
		set_meta(&"mds_grants", PackedStringArray([g]))

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return
	_inside = true
	if auto_collect:
		collect()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or auto_collect or not _inside:
		return
	if InputMap.has_action(&"interact") and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		collect()

## Adds it to the kit and is gone (for good when persistent).
func collect() -> void:
	if is_queued_for_deletion():
		return
	var game := MDSWorldGame.instance
	var kit := MDSGameplay.find(game) if game else null
	if not kit:
		return
	_give(kit)
	if persistent and game:
		game.store_object(self)
	collected.emit(get_item_id(), amount)
	queue_free()

## What collecting gives (subtypes give other things).
func _give(kit: MDSGameplay) -> void:
	if not item:
		return
	kit.register_item(item)
	kit.add_item(item.id, amount)
	kit.notice.emit("%s%s" % [item.get_display_name(), " x%d" % amount if amount > 1 else ""])

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or magnet_radius <= 0.0 or is_queued_for_deletion():
		return
	var game := MDSWorldGame.instance
	var p: Node2D = game.player if game else null
	if p and p.global_position.distance_to(global_position) < magnet_radius:
		global_position = global_position.move_toward(p.global_position, magnet_speed * delta)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var c := Vector2(0, sin(_time * 3.0) * 3.0)
	draw_circle(c, radius * 1.6, Color(color, 0.15))
	if item and item.icon:
		var s := Vector2(radius, radius) * 2.0
		draw_texture_rect(item.icon, Rect2(c - s * 0.5, s), false)
		return
	_draw_shape(c)

## The pickup's look without an icon.
func _draw_shape(c: Vector2) -> void:
	var r := radius
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)]), color)
	draw_circle(c, r * 0.3, Color(1, 1, 1, 0.8))
