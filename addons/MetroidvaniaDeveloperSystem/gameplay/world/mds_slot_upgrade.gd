@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_slot_upgrade.svg")
class_name MDSSlotUpgrade
extends MDSPickup
## A notch for equipment: one more slot ([member MDSGameplay.equip_slots]) for charms. Counted as
## the item [code]equip_slot[/code]; persistent.

func _init() -> void:
	super()
	color = Color(0.85, 0.75, 1.0)
	if not item:
		var d := MDSItemData.new()
		d.id = "equip_slot"
		d.display_name = "Charm Notch"
		d.category = MDSItemData.Category.UPGRADE
		item = d

func _give(kit: MDSGameplay) -> void:
	kit.register_item(item)
	kit.add_item(item.id, amount)
	kit.equip_slots += amount
	kit.equipment_changed.emit()
	kit.notice.emit("Equipment slots: %d" % kit.equip_slots)
