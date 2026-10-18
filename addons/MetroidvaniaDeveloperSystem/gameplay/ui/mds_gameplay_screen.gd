@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_gameplay_screen.svg")
class_name MDSGameplayScreen
extends Control
## The base of the kit's screens that take over the game (pause menu, dialogue, shop, title): it
## covers the screen, pauses the game while open ([member pause_game]; screens opened over one
## another unpause it when the last one closes), keeps running while paused, gives the focus to
## its first control (every screen works with only a gamepad or keyboard) and closes on
## [member close_actions].

signal opened
signal closed

## Pauses the game while it is open.
@export var pause_game := true
## Actions that close it (empty: only code closes it).
@export var close_actions: PackedStringArray = ["ui_cancel"]

static var _pausing := 0
static var _paused_before := false

var _open := false

func _init() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	if not theme:
		theme = MDSGameplayUi.get_theme()

func is_open() -> bool:
	return _open

## Opens it (its contents are built by [method _on_open]).
func open_screen() -> void:
	if _open:
		return
	_open = true
	visible = true
	if pause_game and is_inside_tree():
		if _pausing == 0:
			_paused_before = get_tree().paused
		_pausing += 1
		get_tree().paused = true
	_on_open()
	focus_first.call_deferred()
	opened.emit()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f and is_ancestor_of(f):
		f.release_focus()
	if pause_game:
		_pausing = maxi(0, _pausing - 1)
		var tree := (get_tree() if is_inside_tree() else null)
		if not tree:
			tree = Engine.get_main_loop() as SceneTree
		if _pausing == 0 and tree:
			tree.paused = _paused_before
	_on_close()
	closed.emit()

## Gives the focus to its first control.
func focus_first() -> void:
	if _open:
		MDSGameplayUi.focus_first(self)

## Builds or refreshes its contents (subclasses).
func _on_open() -> void:
	pass

func _on_close() -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	for a in close_actions:
		if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
			get_viewport().set_input_as_handled()
			close()
			return

func _exit_tree() -> void:
	if _open and pause_game:
		_open = false
		_pausing = maxi(0, _pausing - 1)
		var tree := Engine.get_main_loop() as SceneTree
		if _pausing == 0 and tree:
			tree.paused = _paused_before
