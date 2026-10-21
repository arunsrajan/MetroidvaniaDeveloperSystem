@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_dialogue_data.svg")
class_name MDSDialogueData
extends Resource
## A conversation: its lines in order ([MDSDialogueLine]), shown by [MDSDialogueBox].

@export var id := ""
@export var lines: Array[MDSDialogueLine] = []
## How its lines come onto the screen (a line's own [member MDSDialogueLine.reveal] wins). Empty:
## the dialogue box's.
@export var reveal: MDSTextReveal

## A conversation of plain lines by [param speaker] (for code and tests).
static func make(p_id: String, speaker: String, texts: PackedStringArray) -> MDSDialogueData:
	var d := MDSDialogueData.new()
	d.id = p_id
	for t in texts:
		var l := MDSDialogueLine.new()
		l.speaker = speaker
		l.text = t
		d.lines.append(l)
	return d
