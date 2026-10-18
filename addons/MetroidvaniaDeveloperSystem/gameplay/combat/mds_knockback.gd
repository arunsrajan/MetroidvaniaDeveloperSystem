@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_knockback.svg")
class_name MDSKnockback
extends Node
## Pushes its [member body] back when it is hit, and stuns it for [member hitstun_time]: the
## player's Hurt state and enemies wait for [method is_stunned] to end. [member resistance] (and
## the body's knockback resistance in its stats) takes some of the push away.

signal knocked(vector: Vector2)

## The body pushed. Empty: the parent.
@export var body: CharacterBody2D
## 0 to 1: how much of the push is taken away.
@export_range(0.0, 1.0) var resistance := 0.0
@export var hitstun_time := 0.2

var stun_left := 0.0

func _ready() -> void:
	if not body and get_parent() is CharacterBody2D:
		body = get_parent()
	var h := MDSHealth.of(get_parent())
	if h:
		h.damaged.connect(apply)

## Pushes the body with the hit's knockback (from its origin's side).
func apply(info: MDSDamageInfo) -> void:
	if not is_instance_valid(body) or info.knockback == Vector2.ZERO:
		return
	var h := MDSHealth.of(get_parent())
	var stat_res := h.stats.knockback_resistance if h and h.stats else 0.0
	var k := 1.0 - clampf(resistance + stat_res, 0.0, 1.0)
	var v := info.knockback * k
	if info.origin != Vector2.INF and absf(v.x) > 0.0:
		v.x = absf(v.x) * (1.0 if body.global_position.x >= info.origin.x else -1.0)
	body.velocity = v
	stun_left = hitstun_time * k
	knocked.emit(v)

func is_stunned() -> bool:
	return stun_left > 0.0

func _physics_process(delta: float) -> void:
	stun_left = maxf(0.0, stun_left - delta)
