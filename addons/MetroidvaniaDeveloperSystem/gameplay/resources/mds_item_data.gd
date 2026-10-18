@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_item_data.svg")
class_name MDSItemData
extends Resource
## Any pickup that is not an ability: keys, consumables, equipment ([MDSEquipmentData]),
## upgrades and collectibles. [member id] is what [method MDSGameplay.add_item] counts and what
## [code]item:<id>[/code] (or [code]item:<id>>=<n>[/code]) conditions test.

enum Category { KEY, CONSUMABLE, EQUIPMENT, UPGRADE, COLLECTIBLE }

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var category: Category = Category.KEY
## How many can be carried (more are not picked up).
@export var max_stack := 99
## What it sells for, or costs in a shop without a price of its own.
@export var value := 0
## What [method MDSGameplay.use_item] does with it (consumables), or null.
@export var effect: MDSItemEffect

func get_display_name() -> String:
	return display_name if not display_name.is_empty() else id.capitalize()
