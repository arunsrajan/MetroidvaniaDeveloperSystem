@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_ability_popup.svg")
class_name MDSAbilityPopup
extends Control
## Shown when the player gains an ability ([MDSGameplay] calls [method show_ability]): its icon,
## its name, what it does and the key or button of its input action. The game pauses until it is
## closed (jump, attack, interact or accept, after [member min_time]). Put it under the game's UI
## CanvasLayer (Create game scene does); delete it for no popups.

signal closed

## Pause the game while it shows.
@export var pause_game := true
@export var confirm_actions: PackedStringArray = ["ui_accept", "jump", "attack", "interact"]
## Seconds before it can be closed (so a held button doesn't skip it).
@export var min_time := 0.6
## Always show the gamepad button rather than the key. Off: the options' input glyphs choose
## ([method MDSOptions.use_gamepad_glyphs]: keyboard, gamepad, or the gamepad when one is connected).
@export var gamepad_glyphs := false

var _queue: Array[MDSAbilityData] = []
var _current: MDSAbilityData
var _opened := 0
var _paused_it := false
var _icon: TextureRect
var _name: Label
var _desc: Label
var _glyph: Label
var _hint: Label

func _init() -> void:
	add_to_group(&"mds_ability_popup")
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(72, 72)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.add_child(_icon)
	_name = _label(box, 28, HORIZONTAL_ALIGNMENT_CENTER)
	_desc = _label(box, 17, HORIZONTAL_ALIGNMENT_CENTER)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_glyph = _label(box, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_hint = _label(box, 13, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.modulate.a = 0.6

func _label(parent: Node, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", font_size)
	parent.add_child(l)
	return l

## Shows [param data] (after the ones still showing).
func show_ability(data: MDSAbilityData) -> void:
	if not data:
		return
	if visible:
		_queue.append(data)
		return
	_current = data
	_name.text = data.get_display_name()
	_desc.text = data.description
	_icon.texture = data.icon
	_icon.visible = data.icon != null
	var pad := uses_gamepad_glyphs()
	var key := MDSGameplaySetup.glyph(data.input_action, pad) if data.input_action != &"" else ""
	_glyph.text = "[ %s ]" % key if not key.is_empty() else ""
	_hint.text = "Press %s" % MDSGameplaySetup.glyph(&"jump", pad) if InputMap.has_action(&"jump") else ""
	visible = true
	_opened = Time.get_ticks_msec()
	if pause_game and is_inside_tree() and not get_tree().paused:
		get_tree().paused = true
		_paused_it = true

## Whether its glyphs show gamepad buttons: [member gamepad_glyphs], else the options' choice.
func uses_gamepad_glyphs() -> bool:
	return gamepad_glyphs or MDSOptions.use_gamepad_glyphs()

## Whether it is showing an ability.
func is_showing() -> bool:
	return visible

## Closes it (the next queued ability shows, else the game goes on).
func close() -> void:
	visible = false
	_current = null
	if not _queue.is_empty():
		show_ability(_queue.pop_front())
		return
	var tree := (get_tree() if is_inside_tree() else null)
	if not tree:
		tree = Engine.get_main_loop() as SceneTree
	if _paused_it and tree:
		tree.paused = false
	_paused_it = false
	closed.emit()

func _exit_tree() -> void:
	if _paused_it:
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			tree.paused = false
		_paused_it = false

func _input(event: InputEvent) -> void:
	if not visible or Time.get_ticks_msec() - _opened < int(min_time * 1000.0):
		return
	for a in confirm_actions:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			get_viewport().set_input_as_handled()
			close()
			return
