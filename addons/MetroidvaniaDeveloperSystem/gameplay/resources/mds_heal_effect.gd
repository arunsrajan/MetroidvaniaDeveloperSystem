@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_heal_effect.svg")
class_name MDSHealEffect
extends MDSItemEffect
## Restores [member amount] health ([method MDSHealth.heal]).

@export var amount := 1

func apply(target: Node) -> bool:
	var h := MDSHealth.of(target)
	if not h or h.current >= h.get_max():
		return false
	h.heal(amount)
	return true
