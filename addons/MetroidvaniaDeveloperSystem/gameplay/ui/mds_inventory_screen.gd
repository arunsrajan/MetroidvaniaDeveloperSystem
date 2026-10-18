@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_inventory_screen.svg")
class_name MDSInventoryScreen
extends HBoxContainer
## The pause menu's Inventory tab: the items carried by category (keys, consumables, upgrades,
## collectibles; equipment has its own tab), with the focused item's description. Accept uses a
## consumable ([method MDSGameplay.use_item]).

const CATEGORIES: Array[MDSItemData.Category] = [MDSItemData.Category.KEY, MDSItemData.Category.CONSUMABLE, MDSItemData.Category.UPGRADE, MDSItemData.Category.COLLECTIBLE]
const CATEGORY_NAMES: PackedStringArray = ["Keys", "Consumables", "Equipment", "Upgrades", "Collectibles"]

var _list: VBoxContainer
var _desc: Label

func _ready() -> void:
	add_theme_constant_override(&"separation", 18)
	_list = MDSGameplayUi.scroll_list(self)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	add_child(right)
	_desc = MDSGameplayUi.label(right, "", 16, MDSGameplayUi.DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

## Lists the items again.
func refresh() -> void:
	MDSGameplayUi.clear(_list)
	_desc.text = ""
	var kit := MDSGameplayUi.kit_for(self)
	if not kit:
		return
	var any := false
	for cat in CATEGORIES:
		var ids := kit.get_items(cat)
		if ids.is_empty():
			continue
		any = true
		MDSGameplayUi.label(_list, CATEGORY_NAMES[cat], 15, MDSGameplayUi.GOLD)
		for id in ids:
			var d := kit.get_item_data(id)
			var n := kit.get_item_count(id)
			var text := (d.get_display_name() if d else id.capitalize()) + ("  ×%d" % n if n > 1 else "")
			var b := MDSGameplayUi.button(_list, text)
			b.set_meta(&"mds_item", id)
			b.focus_entered.connect(func() -> void: _desc.text = d.description if d else "")
			if d and d.category == MDSItemData.Category.CONSUMABLE:
				b.pressed.connect(_use.bind(id))
	# Items with no data registered (picked up by id only).
	for id in kit.get_items():
		if kit.get_item_data(id) == null:
			any = true
			MDSGameplayUi.button(_list, id.capitalize() + ("  ×%d" % kit.get_item_count(id) if kit.get_item_count(id) > 1 else ""))
	if not any:
		MDSGameplayUi.label(_list, "Nothing yet.", 16, MDSGameplayUi.DIM)

## The item buttons listed.
func get_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in _list.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _use(id: String) -> void:
	var kit := MDSGameplayUi.kit_for(self)
	if kit and kit.use_item(id):
		refresh()
		for b in get_buttons():
			if b.get_meta(&"mds_item", "") == id:
				b.grab_focus()
				return
		MDSGameplayUi.focus_first(self)
