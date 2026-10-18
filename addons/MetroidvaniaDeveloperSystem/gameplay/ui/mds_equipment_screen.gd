@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_equipment_screen.svg")
class_name MDSEquipmentScreen
extends HBoxContainer
## The pause menu's Equipment tab: the charms owned with their slot costs, the ones worn marked,
## the slots used, and the focused charm's effects. Accept puts a charm on or takes it off; away
## from a bench (setting [code]equip_at_bench_only[/code]) it is read-only.

var _list: VBoxContainer
var _slots: Label
var _note: Label
var _desc: Label

func _ready() -> void:
	add_theme_constant_override(&"separation", 18)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	_slots = MDSGameplayUi.label(left, "", 18, MDSGameplayUi.GOLD)
	_note = MDSGameplayUi.label(left, "", 14, MDSGameplayUi.DIM)
	_list = MDSGameplayUi.scroll_list(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	add_child(right)
	_desc = MDSGameplayUi.label(right, "", 16, MDSGameplayUi.DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

## Lists the charms again, keeping the focus on [param focus_id].
func refresh(focus_id := "") -> void:
	MDSGameplayUi.clear(_list)
	var kit := MDSGameplayUi.kit_for(self)
	if not kit:
		return
	var can := kit.can_change_equipment()
	_slots.text = "Slots  %d / %d" % [kit.get_used_slots(), kit.equip_slots]
	_note.text = "" if can else "Rest at a bench to change charms."
	var focus: Button
	var ids := kit.get_items(MDSItemData.Category.EQUIPMENT)
	if ids.is_empty():
		MDSGameplayUi.label(_list, "No charms yet.", 16, MDSGameplayUi.DIM)
	for id in ids:
		var d := kit.get_equipment_data(id)
		if not d:
			continue
		var worn := kit.is_equipped(id)
		var b := MDSGameplayUi.button(_list, "%s %s   (%d)" % ["●" if worn else "○", d.get_display_name(), d.slot_cost])
		b.set_meta(&"mds_item", id)
		b.modulate = Color.WHITE if can else Color(1, 1, 1, 0.6)
		b.pressed.connect(_toggle.bind(id))
		b.focus_entered.connect(func() -> void: _desc.text = describe(d))
		if id == focus_id:
			focus = b
	if focus:
		focus.grab_focus()

## What charm [param d] does, for the description.
static func describe(d: MDSEquipmentData) -> String:
	var lines := PackedStringArray()
	if not d.description.is_empty():
		lines.append(d.description)
	for k in d.stat_mods:
		var v := float(d.stat_mods[k])
		lines.append("%s %s%s" % [str(k).capitalize(), "+" if v >= 0 else "", str(snappedf(v, 0.01)).trim_suffix(".0")])
	for a in d.grants:
		lines.append("Grants %s" % a.capitalize())
	return "\n".join(lines)

## The charm buttons listed.
func get_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in _list.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _toggle(id: String) -> void:
	var kit := MDSGameplayUi.kit_for(self)
	if not kit or not kit.can_change_equipment():
		return
	if kit.is_equipped(id):
		kit.unequip(id)
	elif not kit.equip(id):
		kit.notice.emit("Not enough slots")
	refresh(id)
