@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_corpse.svg")
class_name MDSCorpse
extends Area2D
## Where the player last died, holding the currency it carried (death penalty CORPSE, like Hollow
## Knight's shade). [MDSGameplay] places it when the room of [member MDSGameplay.corpse] loads;
## touching it gives the currency back ([method MDSGameplay.recover_corpse]). Dying again before
## that loses it. Not saved by itself: the kit's save keeps [code]ext.gameplay.corpse[/code].

signal recovered(amount: int)

## The currency it holds (shown over it).
@export var currency := 0
@export var radius := 22.0
@export var color := Color(0.62, 0.66, 0.95)
## Seconds a full bob up and down takes.
@export var bob_time := 2.4

var _t := 0.0
var _label: Label

## Places a corpse holding [param amount] at [param at] (world) in [param room].
static func spawn(room: Node, at: Vector2, amount: int) -> MDSCorpse:
	var c := MDSCorpse.new()
	c.name = "Corpse"
	c.currency = amount
	room.add_child(c)
	c.global_position = at
	return c

func _ready() -> void:
	add_to_group(&"mds_corpse")
	collision_layer = MDSGameplaySetup.bit("interact")
	collision_mask = MDSGameplaySetup.player_detect_mask()
	monitorable = false
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	cs.shape = shape
	add_child(cs)
	_label = Label.new()
	_label.text = str(currency)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_constant_override(&"outline_size", 5)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.position = Vector2(-30, -radius - 34)
	_label.size = Vector2(60, 20)
	add_child(_label)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player") or is_queued_for_deletion():
		return
	var kit := MDSGameplay.find_from(self)
	if kit:
		kit.recover_corpse()
	recovered.emit(currency)
	queue_free()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var bob := sin(_t * TAU / maxf(bob_time, 0.1)) * 4.0
	var c := Vector2(0, bob)
	draw_circle(c, radius * 1.5, Color(color, 0.12))
	draw_circle(c, radius, Color(color, 0.55))
	# A hooded shade: a head and two hollow eyes.
	draw_circle(c + Vector2(0, -radius * 0.25), radius * 0.55, Color(0.08, 0.08, 0.14, 0.9))
	for x in [-0.2, 0.2]:
		draw_circle(c + Vector2(radius * x, -radius * 0.3), radius * 0.1, Color(color, 0.95))
