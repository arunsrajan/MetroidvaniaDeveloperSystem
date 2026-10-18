@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_damage_number.svg")
class_name MDSDamageNumber
extends Node2D
## A hit's damage, floating up from the body it hurt and fading. [MDSHealth] shows one for each
## hit while the kit's [code]feel/damage_numbers[/code] setting is on (off by default). It is put
## in the body's parent, so it stays where the hit was as the body moves on.

## How far (px) it rises, and in how many seconds it is gone.
@export var rise := 36.0
@export var lifetime := 0.7
## Where it starts, from the body's origin.
@export var offset := Vector2(0, -24)
## How far (px) to each side it may start, so numbers of quick hits don't overlap.
@export var jitter := 6.0
@export var color := Color(1.0, 0.92, 0.6)
## The color of the player's own damage.
@export var player_color := Color(1.0, 0.45, 0.4)
## Before the options' text size.
@export var font_size := 18

## The damage shown.
var amount := 0
var label: Label

## Shows [param p_amount] at [param body] (its own damage colored [member player_color] when
## [param is_player]). Returns it, or null when the body has no parent to put it in.
static func spawn(body: Node2D, p_amount: int, is_player := false) -> MDSDamageNumber:
	var parent := body.get_parent() if is_instance_valid(body) else null
	if not parent:
		return null
	var n := MDSDamageNumber.new()
	n.amount = p_amount
	if is_player:
		n.color = n.player_color
	parent.add_child(n)
	n.global_position = body.global_position + n.offset + Vector2(randf_range(-n.jitter, n.jitter), 0.0)
	return n

func _ready() -> void:
	z_index = 50
	label = Label.new()
	label.text = str(amount)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", MDSGameplayUi.font(font_size))
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)
	label.position = -label.get_combined_minimum_size() * 0.5
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "position:y", position.y - rise, lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "modulate:a", 0.0, lifetime * 0.6).set_delay(lifetime * 0.4)
	tw.chain().tween_callback(queue_free)
