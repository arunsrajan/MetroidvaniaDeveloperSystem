@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_shop.svg")
class_name MDSShop
extends MDSNPC
## A shopkeeper: talking to it says its [member dialogue] (a greeting, if any), then opens the
## game's shop screen (the node in group [code]mds_shop_screen[/code], an [MDSShopScreen]) on its
## [member inventory]. Each entry has a price (0: the item's [member MDSItemData.value]), a stock
## (-1: endless) kept in the save ([code]ext.gameplay.shops[/code]) and a condition (an MDS
## condition string) that hides it while unmet.
##
## Bought items are added to the inventory ([method MDSGameplay.add_item]); an UPGRADE with an
## effect (more health, more mana) applies it at once.

signal bought(item: MDSItemData, price: int)
signal shop_opened
signal shop_closed

@export var inventory: MDSShopInventory
## Its key in the save. Empty: its object id (room/path).
@export var shop_id := ""

func _init() -> void:
	prompt = "Shop"
	body_color = Color(0.72, 0.6, 0.38)

## Its key in the save.
func get_shop_id() -> String:
	if not shop_id.is_empty():
		return MDSGameplay.normalize_id(shop_id)
	var g := MDSWorldGame.instance
	return g.object_id(self) if g and g.is_ancestor_of(self) else String(name)

func _entry_id(entry: Dictionary) -> String:
	var item: MDSItemData = entry.get("item")
	return MDSGameplay.normalize_id(item.id) if item else ""

## Entry [param index]'s price.
func get_price(index: int) -> int:
	var e := _entry(index)
	if e.is_empty():
		return 0
	var price := int(e.get("price", 0))
	var item: MDSItemData = e.get("item")
	return price if price > 0 or not item else item.value

## How many of entry [param index] are left (-1: endless).
func get_stock(index: int) -> int:
	var e := _entry(index)
	if e.is_empty():
		return 0
	var kit := get_gameplay()
	var left: Dictionary = kit.shops.get(get_shop_id(), {}) if kit else {}
	return int(left.get(_entry_id(e), int(e.get("stock", -1))))

func _entry(index: int) -> Dictionary:
	if not inventory or index < 0 or index >= inventory.entries.size():
		return {}
	var e: Dictionary = inventory.entries[index]
	return e if e.get("item") is MDSItemData else {}

## What is on sale now: {index, item, price, stock, affordable}, sold-out entries included (stock 0)
## and entries whose condition is unmet left out.
func get_offers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not inventory:
		return out
	var kit := get_gameplay()
	for i in inventory.entries.size():
		var e := _entry(i)
		if e.is_empty() or not condition_met(str(e.get("condition", ""))):
			continue
		var price := get_price(i)
		out.append({"index": i, "item": e.item, "price": price, "stock": get_stock(i), "affordable": kit != null and kit.currency >= price})
	return out

## Whether entry [param index] can be bought now (on sale, in stock, affordable, room to carry).
func can_buy(index: int) -> bool:
	var e := _entry(index)
	var kit := get_gameplay()
	if e.is_empty() or not kit or not condition_met(str(e.get("condition", ""))):
		return false
	if get_stock(index) == 0 or kit.currency < get_price(index):
		return false
	var item: MDSItemData = e.item
	return kit.get_item_count(item.id) < item.max_stack

## Buys one of entry [param index]. Returns whether it was bought.
func buy(index: int) -> bool:
	if not can_buy(index):
		return false
	var kit := get_gameplay()
	var e := _entry(index)
	var item: MDSItemData = e.item
	var price := get_price(index)
	if not kit.spend_currency(price):
		return false
	var stock := get_stock(index)
	if stock > 0:
		var left: Dictionary = kit.shops.get(get_shop_id(), {})
		left[_entry_id(e)] = stock - 1
		kit.shops[get_shop_id()] = left
	kit.register_item(item)
	kit.add_item(item.id)
	if item.category == MDSItemData.Category.UPGRADE and item.effect:
		item.effect.apply(kit.get_game().player if kit.get_game() else null)
	kit.notice.emit("Bought %s" % item.get_display_name())
	bought.emit(item, price)
	return true

## Talks (its greeting), then opens the shop screen. Asynchronous: it returns when the shop closes.
func talk() -> void:
	if talking:
		return
	if get_dialogue():
		await super()
	talking = true
	_show_prompt(false)
	shop_opened.emit()
	var screen := get_tree().get_first_node_in_group(&"mds_shop_screen") if is_inside_tree() else null
	if screen and screen.has_method(&"open"):
		screen.call(&"open", self)
		if screen.has_signal(&"closed") and screen.call(&"is_open"):
			await screen.closed
	talking = false
	_show_prompt(player_near())
	shop_closed.emit()

func _draw() -> void:
	super()
	# A counter in front.
	draw_rect(Rect2(-size.x * 0.8, size.y * 0.1, size.x * 1.6, size.y * 0.4), Color(0.36, 0.25, 0.16))
	draw_rect(Rect2(-size.x * 0.8, size.y * 0.1, size.x * 1.6, 4.0), Color(0.55, 0.4, 0.25))
