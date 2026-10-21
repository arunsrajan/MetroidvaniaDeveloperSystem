@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_dialogue_line.svg")
class_name MDSDialogueLine
extends Resource
## One line of a conversation ([MDSDialogueData]). It is skipped while [member condition] (an
## MDS condition string: [code]dash[/code], [code]item:red_key[/code], [code]flag:met_elder[/code],
## [code]boss:Warden[/code]...) is unmet. Showing it sets [member set_flag]. [member choices]
## ({text, next: line index or -1 to end, set_flag}) let the player answer.
##
## A line [member from_player] is the player's side of the conversation: the dialogue box names
## it after the player ([member MDSDialogueBox.player_name]) and shows its portrait on the right.

@export var speaker := ""
@export_multiline var text := ""
@export var portrait: Texture2D
## The player says it (named and pictured on the right), not the one talked to.
@export var from_player := false
## How it comes onto the screen ([MDSTextRevealLetters], [MDSTextRevealWords]...). Empty: the
## conversation's, else the dialogue box's.
@export var reveal: MDSTextReveal
@export var condition := ""
@export var set_flag := ""
@export var choices: Array[Dictionary] = []
