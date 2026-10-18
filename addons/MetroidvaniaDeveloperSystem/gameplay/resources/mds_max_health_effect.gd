@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_max_health_effect.svg")
class_name MDSMaxHealthEffect
extends MDSItemEffect
## Raises maximum health by [member amount] (kept in the save, see
## [member MDSGameplay.max_health]) and fills it.

@export var amount := 1

func apply(target: Node) -> bool:
	var gp := MDSGameplay.find_from(target)
	if not gp:
		return false
	gp.raise_max_health(amount)
	return true
