@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_dialogue_box.svg")
class_name MDSDialogueBox
extends MDSGameplayScreen
## Shows a conversation ([MDSDialogueData]) at the bottom of the screen: the speaker's name and
## portrait, the text coming in, and the line's choices as buttons. How the text comes is a
## [MDSTextReveal]: letter by letter ([MDSTextRevealLetters]), word by word
## ([MDSTextRevealWords]), at once ([MDSTextReveal]) or a style of your own, set here for every
## line ([member reveal]), on a conversation or on a line; the player's Text speed option
## ([member MDSOptions.text_speed]) scales it. [member advance_actions] show the rest of the line,
## then go to the next one. Lines whose condition is unmet are skipped; a line shown sets its
## flag, a choice picked sets its own and goes to its [code]next[/code] line (-1: the end).
##
## The other side of the conversation is whoever started it: an [MDSNPC] or [MDSShop], an
## [MDSBoss] (its intro and its defeat), an [MDSLoreTablet], an [MDSDialogueTrigger] on any object,
## named by its [code]get_dialogue_name()[/code]. Lines [member MDSDialogueLine.from_player] are
## the player's, named [member player_name] with [member player_portrait] on the right. They find
## it in group [code]mds_dialogue_box[/code]. The game is paused while it is open.

signal line_shown(index: int, line: MDSDialogueLine)
signal choice_made(index: int, choice: Dictionary)
## More of the line came onto the screen: [param count] characters show now (a typing sound).
signal characters_shown(count: int)
signal finished

## How lines come onto the screen when neither the line nor its conversation says. Empty: letter
## by letter at [member chars_per_second].
@export var reveal: MDSTextReveal
## Letters typed per second when [member reveal] is empty (0: the whole line at once).
@export var chars_per_second := 45.0
## The player's Text speed option ([member MDSOptions.text_speed]) scales every line's pace.
@export var use_text_speed_option := true
@export var advance_actions: PackedStringArray = ["ui_accept", "interact", "jump", "attack"]
@export var box_height := 190.0
@export_group("Player")
## The name over the player's lines ([member MDSDialogueLine.from_player]).
@export var player_name := "You"
## The portrait beside the player's lines, on the right (a line's own portrait wins).
@export var player_portrait: Texture2D

var data: MDSDialogueData
var speaker_node: Node
## The line shown (an index of [member data]'s lines; -1: none).
var line_index := -1
## How the line shown comes onto the screen.
var line_reveal: MDSTextReveal
var _elapsed := 0.0
var _panel: PanelContainer
var _portrait: TextureRect
var _portrait_right: TextureRect
var _name: Label
var _text: Label
var _choices: VBoxContainer
var _hint: Label

func _init() -> void:
	super()
	close_actions = []
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	super()
	add_to_group(&"mds_dialogue_box")
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -box_height - 24.0
	_panel.offset_bottom = -24.0
	_panel.offset_left = 48.0
	_panel.offset_right = -48.0
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	_panel.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(128, 128)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_name = MDSGameplayUi.label(col, "", 20, MDSGameplayUi.GOLD)
	_text = MDSGameplayUi.label(col, "", 18)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choices = VBoxContainer.new()
	col.add_child(_choices)
	_hint = MDSGameplayUi.label(col, "", 13, MDSGameplayUi.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_portrait_right = TextureRect.new()
	_portrait_right.custom_minimum_size = Vector2(128, 128)
	_portrait_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_right.visible = false
	row.add_child(_portrait_right)

## Starts [param p_data] (said by [param speaker], an [MDSNPC] or any node). Await
## [signal finished] for its end.
func start(p_data: MDSDialogueData, speaker: Node = null) -> void:
	data = p_data
	speaker_node = speaker
	if not data or data.lines.is_empty():
		finished.emit()
		return
	open_screen()
	_go_to(0)

## The name of [param node] in a conversation: its [code]get_dialogue_name()[/code] (an NPC's, a
## boss's, a dialogue trigger's), else its [code]npc_name[/code], else "".
static func speaker_name(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if node.has_method(&"get_dialogue_name"):
		return str(node.call(&"get_dialogue_name"))
	return str(node.get("npc_name")) if "npc_name" in node else ""

## How [param line] comes onto the screen: its own style, else its conversation's, else the box's,
## else letter by letter at [member chars_per_second] (at once when that is 0).
func reveal_for(line: MDSDialogueLine) -> MDSTextReveal:
	if line and line.reveal:
		return line.reveal
	if data and data.reveal:
		return data.reveal
	if reveal:
		return reveal
	if chars_per_second <= 0.0:
		return MDSTextReveal.new()
	return MDSTextRevealLetters.make(chars_per_second, 0.0, 0.0)

## How fast lines go, times their style's pace: the player's Text speed option (0: whole lines).
func _speed() -> float:
	return MDSOptions.text_speed_scale() if use_text_speed_option else 1.0

## The text on screen now (as much as is typed).
func get_visible_text() -> String:
	return _text.text.substr(0, _text.visible_characters) if _text.visible_characters >= 0 else _text.text

## Whether the line is still being typed.
func is_typing() -> bool:
	return _text.visible_characters >= 0 and _text.visible_characters < _text.text.length()

## The current line's choices (buttons), if any.
func get_choice_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in _choices.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _met(line: MDSDialogueLine) -> bool:
	if not line:
		return false
	if line.condition.strip_edges().is_empty():
		return true
	if speaker_node is MDSNPC:
		return (speaker_node as MDSNPC).condition_met(line.condition)
	var kit := MDSGameplayUi.kit_for(self)
	return kit != null and kit.are_met(PackedStringArray([line.condition]))

## Shows line [param index], or the next one after it whose condition is met; past the end, ends.
func _go_to(index: int) -> void:
	var i := index
	while i >= 0 and i < data.lines.size() and not _met(data.lines[i]):
		i += 1
	if i < 0 or i >= data.lines.size():
		end()
		return
	line_index = i
	var line := data.lines[i]
	if line.from_player:
		_name.text = line.speaker if not line.speaker.is_empty() else player_name
	else:
		_name.text = line.speaker if not line.speaker.is_empty() else speaker_name(speaker_node)
	_name.visible = not _name.text.is_empty()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if line.from_player else HORIZONTAL_ALIGNMENT_LEFT
	var picture := line.portrait if line.portrait or not line.from_player else player_portrait
	_portrait.texture = null if line.from_player else picture
	_portrait.visible = not line.from_player and picture != null
	_portrait_right.texture = picture if line.from_player else null
	_portrait_right.visible = line.from_player and picture != null
	_text.text = line.text
	line_reveal = reveal_for(line)
	_elapsed = 0.0
	MDSGameplayUi.clear(_choices)
	_hint.text = ""
	var kit := MDSGameplayUi.kit_for(self)
	if kit and not line.set_flag.is_empty():
		kit.set_flag(line.set_flag)
	line_shown.emit(i, line)
	_text.visible_characters = 0
	_reveal_more(0.0)

func _line_typed() -> void:
	_text.visible_characters = -1
	var line := data.lines[line_index]
	if line.choices.is_empty():
		_hint.text = "▼"
		return
	for k in line.choices.size():
		var ch: Dictionary = line.choices[k]
		var b := MDSGameplayUi.button(_choices, str(ch.get("text", "…")))
		b.pressed.connect(_choose.bind(k))
	MDSGameplayUi.focus_first(_choices)

func _choose(k: int) -> void:
	var line := data.lines[line_index]
	var ch: Dictionary = line.choices[k]
	var kit := MDSGameplayUi.kit_for(self)
	if kit and not str(ch.get("set_flag", "")).is_empty():
		kit.set_flag(str(ch.set_flag))
	choice_made.emit(k, ch)
	var next := int(ch.get("next", line_index + 1))
	if next < 0:
		end()
	else:
		_go_to(next)

## Skips the typing, or goes on to the next line.
func advance() -> void:
	if not is_open() or line_index < 0:
		return
	if is_typing():
		_line_typed()
		return
	if not get_choice_buttons().is_empty():
		return
	_go_to(line_index + 1)

## Ends the conversation.
func end() -> void:
	line_index = -1
	MDSGameplayUi.clear(_choices)
	close()
	finished.emit()

func _process(delta: float) -> void:
	if not is_open() or line_index < 0 or not is_typing():
		return
	_reveal_more(delta)

## Lets [param delta] seconds of the line's reveal go by (times the Text speed option); all of it
## shows at once with Instant.
func _reveal_more(delta: float) -> void:
	var speed := _speed()
	var n := _text.text.length()
	if speed > 0.0 and line_reveal:
		_elapsed += delta * speed
		n = clampi(line_reveal.visible_characters(_text.text, _elapsed), 0, n)
	if n > _text.visible_characters:
		_text.visible_characters = n
		characters_shown.emit(n)
	if n >= _text.text.length():
		_line_typed()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	for a in advance_actions:
		if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
			get_viewport().set_input_as_handled()
			advance()
			return
