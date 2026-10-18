@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_dialogue_line.svg")
class_name MDSDialogueLine
extends Resource
## One line of a conversation ([MDSDialogueData]). It is skipped while [member condition] (an
## MDS condition string: [code]dash[/code], [code]item:red_key[/code], [code]flag:met_elder[/code],
## [code]boss:Warden[/code]...) is unmet. Showing it sets [member set_flag]. [member choices]
## ({text, next: line index or -1 to end, set_flag}) let the player answer.

@export var speaker := ""
@export_multiline var text := ""
@export var portrait: Texture2D
@export var condition := ""
@export var set_flag := ""
@export var choices: Array[Dictionary] = []
