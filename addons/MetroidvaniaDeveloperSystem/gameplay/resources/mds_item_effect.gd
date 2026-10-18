@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_item_effect.svg")
class_name MDSItemEffect
extends Resource
## What using an item does ([method MDSGameplay.use_item]): override [method apply]. The
## built-ins are [MDSHealEffect], [MDSMaxHealthEffect], [MDSManaEffect] and [MDSBuffEffect].

## Applies the effect to [param target] (the player, usually an [MDSPlayer]). Returns whether it
## did something (an item used for nothing is not used up).
func apply(_target: Node) -> bool:
	return false
