@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_lore_tablet.svg")
class_name MDSLoreTablet
extends Area2D
## An ancient stone tablet that can be inspected by the player. Reading it adds a
## Journal entry (flag [code]journal_<tablet_id>[/code]) containing its title and text,
## and presents the lore through the game's [MDSDialogueBox] (or a toast).

signal read_tablet

@export var tablet_id := "":
	set(v):
		tablet_id = v
		if title.is_empty() and not tablet_id.is_empty():
			title = tablet_id.capitalize()
@export var title := ""
@export_multiline var text := ""
@export var prompt := "Inspect"
@export var size := Vector2(32, 48):
	set(v):
		size = v
		queue_redraw()
@export var tablet_color := Color(0.6, 0.62, 0.65):
	set(v):
		tablet_color = v
		queue_redraw()

var reading := false
var _inside: Node2D
var _label: Label

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	add_to_group(&"mds_lore_tablet")
	add_to_group(&"mds_stands")
	collision_layer = MDSGameplaySetup.bit("interact")
	collision_mask = MDSGameplaySetup.player_detect_mask()

	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = size + Vector2(32, 0)
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

func _draw() -> void:
	var r := Rect2(-size.x * 0.5, -size.y, size.x, size.y)
	# Draw carved stone slab
	draw_rect(r, tablet_color)
	draw_rect(r, tablet_color.darkened(0.35), false, 2.0)
	# Inscription lines
	var line_color := tablet_color.darkened(0.5)
	var count := 4
	var step := (size.y - 16.0) / float(count + 1)
	for i in count:
		var y := -size.y + 12.0 + step * (i + 1)
		draw_line(Vector2(-size.x * 0.35, y), Vector2(size.x * 0.35, y), line_color, 1.5)

func _unhandled_input(event: InputEvent) -> void:
	if not _inside or reading:
		return
	if InputMap.has_action(&"interact") and event.is_action_pressed(&"interact", false, true):
		get_viewport().set_input_as_handled()
		inspect()

## Inspects and reads the tablet.
func inspect() -> void:
	if reading:
		return
	reading = true
	var id := tablet_id if not tablet_id.is_empty() else String(name).to_snake_case()
	var heading := title if not title.is_empty() else id.capitalize()
	var content := text if not text.is_empty() else heading

	var kit := MDSGameplay.find_from(self)
	if kit:
		kit.set_flag("journal_" + id, {"title": heading, "text": content})

	read_tablet.emit()

	var box := get_tree().get_first_node_in_group(&"mds_dialogue_box") as MDSDialogueBox
	if box:
		var data := MDSDialogueData.new()
		data.id = "lore_" + id
		var line := MDSDialogueLine.new()
		line.speaker = heading
		line.text = content
		data.lines = [line]
		box.start(data, self)
		await box.finished
	else:
		var toast := get_tree().get_first_node_in_group(&"mds_toast") as MDSToast
		if toast:
			toast.show_toast(heading)

	reading = false

func _show_prompt(on: bool) -> void:
	if on and not _label:
		_label = Label.new()
		_label.text = prompt
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.position = Vector2(-60, -size.y - 28)
		_label.size = Vector2(120, 20)
		_label.add_theme_color_override(&"font_color", MDSGameplayUi.GOLD)
		_label.add_theme_font_size_override(&"font_size", 14)
		add_child(_label)
	elif not on and _label:
		_label.queue_free()
		_label = null
