@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_dialogue_trigger.svg")
class_name MDSDialogueTrigger
extends Area2D
## A conversation with anything: put it on (or beside) a door, a chest, a statue, a sign, a
## lever, a sleeping boss, and the player talks to that. Standing in it shows [member prompt] and
## pressing [code]interact[/code] starts [member dialogue] in the game's [MDSDialogueBox]
## (INTERACT), or the conversation starts as the player walks in (TOUCH).
##
## [member alt_dialogues] ({condition, dialogue}) replace [member dialogue] as the story moves on:
## the first whose MDS condition string is met wins. While [member condition] is unmet it stays
## silent. With [member once] it has its say the first time only (kept like a collected item,
## also after a save and load). The other side of the conversation is [member speaker_name], else
## its parent's name in conversations ([code]get_dialogue_name()[/code]: an NPC's, a boss's), else
## the parent node's name. Its area of [member size] stands on its origin. Without a dialogue box
## in the game, the lines' flags are set at once.

signal started(dialogue: MDSDialogueData)
signal ended

enum Trigger { INTERACT, TOUCH }

@export var dialogue: MDSDialogueData
## {"condition": String, "dialogue": MDSDialogueData}, the first met wins.
@export var alt_dialogues: Array[Dictionary] = []
@export var trigger: Trigger = Trigger.INTERACT
## Who speaks (empty: its parent's name, see the class description).
@export var speaker_name := ""
## Shown over it while the player can talk (INTERACT).
@export var prompt := "Look"
## Only the first time (kept in the save).
@export var once := false
## Silent while this MDS condition string is unmet (empty: always talks).
@export var condition := ""
## Its area, standing on its origin.
@export var size := Vector2(64, 96):
	set(v):
		size = v.max(Vector2(8, 8))
		queue_redraw()

var talking := false
var _inside: Node2D
var _label: Label

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	add_to_group(&"mds_dialogue_trigger")
	collision_layer = MDSGameplaySetup.bit("interact")
	collision_mask = MDSGameplaySetup.player_detect_mask()
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = size
		cs.shape = r
		cs.position = Vector2(0, -size.y * 0.5)
		add_child(cs)
	body_entered.connect(func(b: Node) -> void:
		if not b.is_in_group(&"player") or not b is Node2D:
			return
		_inside = b
		if trigger == Trigger.TOUCH:
			start()
		else:
			_show_prompt(can_talk()))
	body_exited.connect(func(b: Node) -> void:
		if b == _inside:
			_inside = null
			_show_prompt(false))

func get_gameplay() -> MDSGameplay:
	return MDSGameplay.find_from(self)

## The name it speaks with in conversations.
func get_dialogue_name() -> String:
	if not speaker_name.is_empty():
		return speaker_name
	var p := get_parent()
	if p and p.has_method(&"get_dialogue_name"):
		return str(p.call(&"get_dialogue_name"))
	return String(p.name).capitalize() if p else ""

## Whether MDS condition [param c] is met now (empty: yes).
func condition_met(c: String) -> bool:
	if c.strip_edges().is_empty():
		return true
	var kit := get_gameplay()
	return kit != null and kit.are_met(PackedStringArray([c]))

## The conversation it has now: the first [member alt_dialogues] entry whose condition is met,
## else [member dialogue].
func get_dialogue() -> MDSDialogueData:
	for entry in alt_dialogues:
		var d: Variant = entry.get("dialogue")
		if d is MDSDialogueData and condition_met(str(entry.get("condition", ""))):
			return d
	return dialogue

## Whether it had its one say already ([member once]).
func is_spent() -> bool:
	var game := MDSWorldGame.instance
	return once and game != null and game.is_object_stored(self)

## Whether it would talk now.
func can_talk() -> bool:
	return not talking and not is_spent() and condition_met(condition) and get_dialogue() != null

## Starts its conversation. Asynchronous: it returns when the conversation ends.
func start() -> void:
	if not can_talk() or not is_inside_tree():
		return
	var d := get_dialogue()
	talking = true
	_show_prompt(false)
	var game := MDSWorldGame.instance
	if once and game:
		game.store_object(self)
	started.emit(d)
	var box := get_tree().get_first_node_in_group(&"mds_dialogue_box")
	if box and box.has_method(&"start"):
		box.call(&"start", d, self)
		if box.has_signal(&"finished") and box.call(&"is_open"):
			await box.finished
	else:
		var kit := get_gameplay()
		for l in d.lines:
			if kit and l and not l.set_flag.is_empty() and condition_met(l.condition):
				kit.set_flag(l.set_flag)
	talking = false
	_show_prompt(is_instance_valid(_inside) and trigger == Trigger.INTERACT and can_talk())
	ended.emit()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or trigger != Trigger.INTERACT or not is_instance_valid(_inside) or not can_talk():
		return
	if InputMap.has_action(&"interact") and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		start()

func _show_prompt(on: bool) -> void:
	if prompt.is_empty():
		return
	if on and not _label:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_constant_override(&"outline_size", 5)
		_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		_label.z_index = 40
		add_child(_label)
	if _label:
		_label.text = prompt
		_label.reset_size()
		_label.position = Vector2(-_label.size.x / 2.0, -size.y - 30.0)
		_label.visible = on

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var r := Rect2(-size.x * 0.5, -size.y, size.x, size.y)
	draw_rect(r, Color(0.45, 0.6, 0.85, 0.12))
	draw_rect(r, Color(0.45, 0.6, 0.85, 0.8), false, 1.5)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 14), "Dialogue" + (": " + dialogue.id if dialogue and not dialogue.id.is_empty() else ""), HORIZONTAL_ALIGNMENT_LEFT, size.x - 8.0, 12, Color(0.7, 0.85, 1.0))
