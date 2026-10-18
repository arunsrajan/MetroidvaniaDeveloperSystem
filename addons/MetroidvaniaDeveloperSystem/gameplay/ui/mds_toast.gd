@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_toast.svg")
class_name MDSToast
extends Control
## Short notices at the top of the screen, one after another: what the kit announces
## ([signal MDSGameplay.notice]: an item picked up, "Requires Dash" when a gate won't let the
## player through, a level), and "Map updated" when a bench saves rooms visited since the last
## save. [method show_text] adds one of your own.

## Seconds each notice stays.
@export var show_time := 2.2
@export var fade_time := 0.25
## Notices waiting beyond this are dropped (the oldest first).
@export var max_queue := 6
@export var map_updated_text := "Map updated"

var _panel: PanelContainer
var _label: Label
var _queue: PackedStringArray = []
var _left := 0.0
var _current := ""
var _rooms_at_save := -1

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not theme:
		theme = MDSGameplayUi.get_theme()
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = MDSGameplayUi.label(_panel, "", 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.visible = false
	_connect.call_deferred()

func _connect() -> void:
	var game := MDSGameplayUi.game_for(self)
	var kit := MDSGameplay.find(game) if game else null
	if kit:
		kit.notice.connect(show_text)
	if game:
		_rooms_at_save = game.visited_rooms.size()
		game.game_saved.connect(func(_p: Node) -> void:
			if _rooms_at_save >= 0 and game.visited_rooms.size() > _rooms_at_save:
				show_text(map_updated_text)
			_rooms_at_save = game.visited_rooms.size())
		game.game_loaded.connect(func() -> void: _rooms_at_save = game.visited_rooms.size())

## Shows [param text] (after the notices before it).
func show_text(text: String) -> void:
	if text.is_empty():
		return
	if _current.is_empty():
		_show(text)
	else:
		_queue.append(text)
		while _queue.size() > max_queue:
			_queue.remove_at(0)

## The notice on screen ("" when none).
func get_current_text() -> String:
	return _current

func is_showing() -> bool:
	return not _current.is_empty()

## Every notice shown or waiting.
func get_queue() -> PackedStringArray:
	return _queue.duplicate()

func _show(text: String) -> void:
	_current = text
	_label.text = text
	_left = show_time
	_panel.visible = true
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.size.x) * 0.5, 64.0)
	_panel.modulate.a = 0.0

func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_left -= delta
	var shown := show_time - _left
	_panel.modulate.a = clampf(minf(shown, _left) / maxf(fade_time, 0.01), 0.0, 1.0)
	if _left <= 0.0:
		_current = ""
		_panel.visible = false
		if not _queue.is_empty():
			var next := _queue[0]
			_queue.remove_at(0)
			_show(next)
