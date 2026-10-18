@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_mana_upgrade.svg")
class_name MDSManaUpgrade
extends MDSPickup
## A mana fragment: every [member fragments_per_upgrade] of them raise maximum mana by
## [member mana_per_upgrade]. Counted as the item [code]mana_fragment[/code]; persistent.

@export var fragments_per_upgrade := 3
@export var mana_per_upgrade := 33

func _init() -> void:
	super()
	color = Color(0.45, 0.65, 1.0)
	if not item:
		var d := MDSItemData.new()
		d.id = "mana_fragment"
		d.display_name = "Mana Fragment"
		d.category = MDSItemData.Category.UPGRADE
		item = d

func _give(kit: MDSGameplay) -> void:
	kit.register_item(item)
	var n := kit.add_item(item.id, amount)
	if fragments_per_upgrade > 0 and n % fragments_per_upgrade == 0:
		kit.raise_max_mana(mana_per_upgrade)
		kit.notice.emit("Maximum mana up")
	else:
		kit.notice.emit("Mana fragment %d / %d" % [n % maxi(1, fragments_per_upgrade), fragments_per_upgrade])
