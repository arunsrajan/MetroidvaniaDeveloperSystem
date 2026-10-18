@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_health_upgrade.svg")
class_name MDSHealthUpgrade
extends MDSPickup
## A health fragment: every [member fragments_per_upgrade] of them raise maximum health by one
## ([method MDSGameplay.raise_max_health]). They are counted as the item
## [code]health_fragment[/code] (so [code]item:health_fragment>=4[/code] works) and are persistent.

@export var fragments_per_upgrade := 4

func _init() -> void:
	super()
	color = Color(0.95, 0.45, 0.5)
	if not item:
		item = _fragment()

static func _fragment() -> MDSItemData:
	var d := MDSItemData.new()
	d.id = "health_fragment"
	d.display_name = "Health Fragment"
	d.description = "Four make one more health."
	d.category = MDSItemData.Category.UPGRADE
	return d

func _give(kit: MDSGameplay) -> void:
	kit.register_item(item)
	var n := kit.add_item(item.id, amount)
	if fragments_per_upgrade > 0 and n % fragments_per_upgrade == 0:
		kit.raise_max_health(1)
		kit.notice.emit("Maximum health up")
	else:
		kit.notice.emit("Health fragment %d / %d" % [n % maxi(1, fragments_per_upgrade), fragments_per_upgrade])

func _draw_shape(c: Vector2) -> void:
	var r := radius
	var heart := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		heart.append(c + Vector2(16.0 * pow(sin(t), 3.0), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * r / 17.0)
	draw_colored_polygon(heart, color)
