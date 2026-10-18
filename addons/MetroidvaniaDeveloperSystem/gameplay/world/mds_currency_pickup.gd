@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_currency_pickup.svg")
class_name MDSCurrencyPickup
extends MDSPickup
## Currency (Hollow Knight's geo): [member amount] of it, pulled to the player who comes near, never
## persistent. Enemies drop it.

func _init() -> void:
	super()
	persistent = false
	magnet_radius = 160.0
	radius = 8.0
	color = Color(1.0, 0.9, 0.5)

func _give(kit: MDSGameplay) -> void:
	kit.add_currency(amount)

func get_grant() -> String:
	return ""

func _draw_shape(c: Vector2) -> void:
	draw_circle(c, radius, color)
	draw_circle(c + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.35, Color(1, 1, 1, 0.7))
	draw_arc(c, radius, 0, TAU, 16, color.darkened(0.35), 1.5)
