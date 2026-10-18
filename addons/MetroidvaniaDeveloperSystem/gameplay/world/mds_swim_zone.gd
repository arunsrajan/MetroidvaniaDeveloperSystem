@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_swim_zone.svg")
class_name MDSSwimZone
extends Area2D
## Water the player is in: with the [code]swim[/code] ability it swims freely, without it it sinks
## slowly and moves slower. [MDSWater] makes one over its rectangle when its
## [member MDSWater.swimmable] is on; add one yourself for water of your own. [member size] is
## centred on the node.

@export var size := Vector2(480, 200)

func _ready() -> void:
	collision_layer = 0
	collision_mask = MDSGameplaySetup.player_detect_mask()
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = size
		cs.shape = r
		add_child(cs)
	body_entered.connect(func(b: Node) -> void:
		if b is MDSPlayer and not (b as MDSPlayer).water_zones.has(self):
			(b as MDSPlayer).water_zones.append(self))
	body_exited.connect(func(b: Node) -> void:
		if b is MDSPlayer:
			(b as MDSPlayer).water_zones.erase(self))
