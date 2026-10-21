@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_npc.svg")
class_name MDSNPC
extends Area2D
## A character to talk to. Standing at it shows [member prompt] over it (like an [MDSGate]'s);
## pressing [code]interact[/code] starts its conversation ([method talk]) in the game's
## [MDSDialogueBox] (the node in group [code]mds_dialogue_box[/code]).
##
## [member alt_dialogues] ({condition, dialogue}) replace [member dialogue] as the story moves on:
## the first whose MDS condition string ([code]boss:Warden[/code], [code]flag:met_elder[/code],
## [code]item:red_key[/code], an ability) is met wins. Lines are skipped while their own condition
## is unmet and set their flag when shown; with no dialogue box in the game the flags are set at
## once. NPCs that move with the story can check a flag when their room loads, or use MDS's
## [code]carry_over[/code] group.

signal talked(dialogue: MDSDialogueData)
signal conversation_ended

@export var npc_name := "":
	set(v):
		npc_name = v
		queue_redraw()
@export var dialogue: MDSDialogueData
## {"condition": String, "dialogue": MDSDialogueData}, the first met wins.
@export var alt_dialogues: Array[Dictionary] = []
## Shown over it while the player can talk ({name}: [member npc_name]).
@export var prompt := "Talk"
@export var size := Vector2(36, 64):
	set(v):
		size = v
		queue_redraw()
@export var body_color := Color(0.55, 0.62, 0.78):
	set(v):
		body_color = v
		queue_redraw()
## Turns toward the player standing at it.
@export var face_player := true

var facing := -1
var talking := false
var _inside: Node2D
var _label: Label

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	add_to_group(&"mds_npc")
	collision_layer = MDSGameplaySetup.bit("interact")
	collision_mask = MDSGameplaySetup.player_detect_mask()
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = size + Vector2(48, 0)
		cs.shape = r
		add_child(cs)
	body_entered.connect(func(b: Node) -> void:
		if b.is_in_group(&"player") and b is Node2D:
			_inside = b
			_show_prompt(true))
	body_exited.connect(func(b: Node) -> void:
		if b == _inside:
			_inside = null
			_show_prompt(false))

func get_gameplay() -> MDSGameplay:
	return MDSGameplay.find_from(self)

## The name it speaks with in conversations ([member npc_name]).
func get_dialogue_name() -> String:
	return npc_name

## Whether MDS condition [param condition] is met now (empty: yes).
func condition_met(condition: String) -> bool:
	if condition.strip_edges().is_empty():
		return true
	var kit := get_gameplay()
	return kit != null and kit.are_met(PackedStringArray([condition]))

## The conversation it has now: the first [member alt_dialogues] entry whose condition is met,
## else [member dialogue].
func get_dialogue() -> MDSDialogueData:
	for entry in alt_dialogues:
		var d: Variant = entry.get("dialogue")
		if d is MDSDialogueData and condition_met(str(entry.get("condition", ""))):
			return d
	return dialogue

## The lines of [param data] shown now (those whose condition is met).
func get_lines(data: MDSDialogueData) -> Array[MDSDialogueLine]:
	var out: Array[MDSDialogueLine] = []
	if data:
		for l in data.lines:
			if l and condition_met(l.condition):
				out.append(l)
	return out

## Whether the player is standing at it.
func player_near() -> bool:
	return is_instance_valid(_inside)

## Starts its conversation. Asynchronous: it returns when the conversation ends.
func talk() -> void:
	if talking:
		return
	var d := get_dialogue()
	if not d:
		return
	talking = true
	_show_prompt(false)
	talked.emit(d)
	var box := get_tree().get_first_node_in_group(&"mds_dialogue_box") if is_inside_tree() else null
	if box and box.has_method(&"start"):
		box.call(&"start", d, self)
		if box.has_signal(&"finished") and box.call(&"is_open"):
			await box.finished
	else:
		var kit := get_gameplay()
		for l in get_lines(d):
			if kit and not l.set_flag.is_empty():
				kit.set_flag(l.set_flag)
	talking = false
	_show_prompt(player_near())
	conversation_ended.emit()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or talking or not player_near():
		return
	if InputMap.has_action(&"interact") and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		talk()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not face_player or not player_near():
		return
	var f := 1 if _inside.global_position.x >= global_position.x else -1
	if f != facing:
		facing = f
		queue_redraw()

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
		_label.text = prompt.replace("{name}", npc_name)
		_label.reset_size()
		_label.position = Vector2(-_label.size.x / 2.0, -size.y * 0.5 - 34.0)
		_label.visible = on

func _draw() -> void:
	var h := size.y
	var w := size.x
	# A robed figure: body, head, eye on its facing side.
	var body := PackedVector2Array([Vector2(-w * 0.5, h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(w * 0.3, -h * 0.15), Vector2(-w * 0.3, -h * 0.15)])
	draw_colored_polygon(body, body_color)
	var head := Vector2(0, -h * 0.3)
	draw_circle(head, w * 0.32, body_color.lightened(0.25))
	draw_circle(head + Vector2(facing * w * 0.12, -2), 2.5, Color(0.1, 0.1, 0.15))
