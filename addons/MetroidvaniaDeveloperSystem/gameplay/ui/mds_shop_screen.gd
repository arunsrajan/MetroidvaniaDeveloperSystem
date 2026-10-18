@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_shop_screen.svg")
class_name MDSShopScreen
extends MDSGameplayScreen
## The screen an [MDSShop] opens (it finds it in group [code]mds_shop_screen[/code]): what is on
## sale with prices and stock, the item's description, the currency carried. Accept buys the
## focused entry; cancel leaves. The game is paused while it is open.

var shop: MDSShop
var _list: VBoxContainer
var _title: Label
var _desc: Label
var _money: Label

func _ready() -> void:
	super()
	add_to_group(&"mds_shop_screen")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 420)
	panel.position = -panel.custom_minimum_size * 0.5
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	panel.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	_title = MDSGameplayUi.label(top, "Shop", 22, MDSGameplayUi.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money = MDSGameplayUi.label(top, "", 20, MDSGameplayUi.GOLD)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 16)
	col.add_child(row)
	_list = MDSGameplayUi.scroll_list(row)
	_desc = MDSGameplayUi.label(row, "", 16, MDSGameplayUi.DIM)
	_desc.custom_minimum_size = Vector2(240, 0)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MDSGameplayUi.button(col, "Leave", close)

## Opens on [param p_shop]'s wares.
func open(p_shop: MDSShop) -> void:
	shop = p_shop
	open_screen()

func _on_open() -> void:
	_title.text = shop.npc_name if shop and not shop.npc_name.is_empty() else "Shop"
	refresh()

## Lists the offers again (after a purchase), keeping the focus on entry [param focus_index].
func refresh(focus_index := -1) -> void:
	MDSGameplayUi.clear(_list)
	var kit := MDSGameplayUi.kit_for(self)
	_money.text = "◆ %d" % (kit.currency if kit else 0)
	if not shop:
		return
	var focus: Button
	for o in shop.get_offers():
		var item: MDSItemData = o.item
		var stock := int(o.stock)
		var text := "%s   ◆ %d" % [item.get_display_name(), int(o.price)]
		if stock == 0:
			text += "   (sold out)"
		elif stock > 0:
			text += "   (%d left)" % stock
		var b := MDSGameplayUi.button(_list, text)
		b.set_meta(&"mds_index", int(o.index))
		b.modulate = Color.WHITE if shop.can_buy(int(o.index)) else Color(1, 1, 1, 0.5)
		b.pressed.connect(_buy.bind(int(o.index)))
		b.focus_entered.connect(func() -> void: _desc.text = item.description)
		if int(o.index) == focus_index:
			focus = b
	if focus:
		focus.grab_focus.call_deferred()

## The offer buttons listed.
func get_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in _list.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _buy(index: int) -> void:
	if shop and shop.buy(index):
		refresh(index)
