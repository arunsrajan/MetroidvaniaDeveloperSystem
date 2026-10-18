@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_shop_inventory.svg")
class_name MDSShopInventory
extends Resource
## What a shop ([MDSShop]) sells: each entry {item: MDSItemData, price (0: the item's value),
## stock (-1: endless), condition (an MDS condition string; empty: always)}. The stock left is
## kept in the save.

@export var entries: Array[Dictionary] = []
