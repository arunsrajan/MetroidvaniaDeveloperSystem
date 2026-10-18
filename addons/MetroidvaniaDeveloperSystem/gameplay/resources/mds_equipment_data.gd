@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_equipment_data.svg")
class_name MDSEquipmentData
extends MDSItemData
## A charm: equipped while resting on a bench ([method MDSGameplay.equip]), it costs
## [member slot_cost] of the player's [member MDSGameplay.equip_slots], changes stats while
## equipped ([member stat_mods]: [code]max_health[/code], [code]max_mana[/code],
## [code]defense[/code], [code]damage[/code], or any [MDSMovementConfig] field, added) and
## lends abilities ([member grants]) that are not kept when it is taken off.

@export var slot_cost := 1
## Stat -> amount added while equipped ({"max_run_speed": 40, "damage": 1}).
@export var stat_mods: Dictionary = {}
## Abilities active while equipped (not written to [member MDSWorldGame.abilities]).
@export var grants: PackedStringArray = []

func _init() -> void:
	category = Category.EQUIPMENT
