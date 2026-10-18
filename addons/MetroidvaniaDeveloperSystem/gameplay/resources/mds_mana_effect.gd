@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_mana_effect.svg")
class_name MDSManaEffect
extends MDSItemEffect
## Restores [member amount] mana, and raises maximum mana by [member max_up].

@export var amount := 33
@export var max_up := 0

func apply(target: Node) -> bool:
	var gp := MDSGameplay.find_from(target)
	if not gp:
		return false
	if max_up > 0:
		gp.raise_max_mana(max_up)
	if amount > 0 and gp.mana < gp.player_max_mana():
		gp.set_mana(gp.mana + amount)
		return true
	return max_up > 0
