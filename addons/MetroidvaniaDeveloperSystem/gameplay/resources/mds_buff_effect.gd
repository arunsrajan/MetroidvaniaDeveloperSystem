@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_buff_effect.svg")
class_name MDSBuffEffect
extends MDSItemEffect
## For [member duration] seconds, adds [member amount] to a stat of the player:
## [code]damage[/code], [code]defense[/code], or a field of its [MDSMovementConfig]
## ([code]max_run_speed[/code]...). See [method MDSPlayer.add_buff].

@export var stat := "damage"
@export var amount := 1.0
@export var duration := 30.0

func apply(target: Node) -> bool:
	if not target or not target.has_method(&"add_buff"):
		return false
	target.call(&"add_buff", stat, amount, duration)
	return true
