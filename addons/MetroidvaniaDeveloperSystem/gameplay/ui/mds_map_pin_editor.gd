@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_map_pin_editor.svg")
class_name MDSMapPinEditor
extends PanelContainer
## A box to write a pin of the player's own on the map: its title, a short description and its
## kind ([member kinds]: a flag, a note, a danger...). [MDSPauseMenu]'s map opens it on a click
## on the map, on Pin where I am, and on a click on one of the player's own pins (to change it,
## or Remove it). OK (or Enter in the title) says [signal confirmed], Cancel (or Esc, B)
## [signal cancelled]. It works with the keyboard and the gamepad (its fields are in the focus
## order; on a phone the screen keyboard opens for them).
##
## In a menu of your own: [method open_new] or [method open_edit], then put the pin with
## [method MDSWorldGame.add_map_marker] when it is confirmed.
## [codeblock]
## editor.confirmed.connect(func(title, description, kind):
##     game.add_map_marker(editor.world_pos, kind, title, description,
##             {"id": editor.pin_id, "layer": editor.map_layer, "player": true}))
## [/codeblock]

## OK: the pin as written.
signal confirmed(title: String, description: String, kind: String)
## Remove, on a pin being changed.
signal removed
signal cancelled

## The kinds the player picks from (see [member MDSWorldMapView.marker_kinds]).
@export var kinds: PackedStringArray = ["pin", "note", "danger", "treasure", "key", "quest"]
## The longest title.
@export var title_length := 40

var heading: Label
var title_edit: LineEdit
var description_edit: TextEdit
var kind_option: OptionButton
var ok_button: Button
var remove_button: Button
var cancel_button: Button
## The pin being written: its id ("" for a new one), where it goes (world px) and its layer.
var pin_id := ""
var world_pos := Vector2.ZERO
var map_layer := 0

func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	heading = MDSGameplayUi.label(box, "New pin", 18, MDSGameplayUi.GOLD)
	var field := MDSGameplayUi._box(Color(0.1, 0.1, 0.13, 1.0), Color(1, 1, 1, 0.15), 1, 4, 6)
	var focused := MDSGameplayUi._box(Color(0.12, 0.12, 0.16, 1.0), MDSGameplayUi.GOLD, 2, 4, 6)
	title_edit = LineEdit.new()
	title_edit.placeholder_text = "Title"
	title_edit.max_length = title_length
	title_edit.add_theme_stylebox_override(&"normal", field)
	title_edit.add_theme_stylebox_override(&"focus", focused)
	title_edit.text_submitted.connect(func(_t: String) -> void: confirm())
	box.add_child(title_edit)
	description_edit = TextEdit.new()
	description_edit.placeholder_text = "Description (what is here, what to do)"
	description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	description_edit.custom_minimum_size = Vector2(0, 76)
	description_edit.add_theme_stylebox_override(&"normal", field)
	description_edit.add_theme_stylebox_override(&"focus", focused)
	box.add_child(description_edit)
	kind_option = OptionButton.new()
	kind_option.tooltip_text = "How it looks on the map"
	box.add_child(kind_option)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 8)
	box.add_child(row)
	remove_button = MDSGameplayUi.button(row, "Remove", remove)
	cancel_button = MDSGameplayUi.button(row, "Cancel", cancel)
	ok_button = MDSGameplayUi.button(row, "OK", confirm)
	# Centred on what it is put in, growing both ways.
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

func _fill_kinds(selected: String) -> void:
	kind_option.clear()
	var list := kinds.duplicate()
	if not selected.is_empty() and not selected in list:
		list.append(selected)
	for k in list:
		var kd: Dictionary = MDSWorldMapView.marker_kinds.get(k, {})
		kind_option.add_item(str(kd.get("name", k.capitalize())))
		kind_option.set_item_metadata(kind_option.item_count - 1, k)
		if k == selected:
			kind_option.select(kind_option.item_count - 1)

## Opens it to write a new pin at [param at] (world px) on [param p_layer].
func open_new(at: Vector2, p_layer: int, kind := "pin") -> void:
	pin_id = ""
	world_pos = at
	map_layer = p_layer
	heading.text = "New pin"
	title_edit.text = ""
	description_edit.text = ""
	_fill_kinds(kind)
	remove_button.visible = false
	_show()

## Opens it to change pin [param id] ([param marker]: its {position, layer, kind, label,
## description}).
func open_edit(id: String, marker: Dictionary) -> void:
	pin_id = id
	world_pos = MDSWorldMapView.pin_position(marker)
	map_layer = int(marker.get("layer", 0))
	heading.text = "Pin"
	title_edit.text = str(marker.get("label", ""))
	description_edit.text = str(marker.get("description", ""))
	_fill_kinds(str(marker.get("kind", "pin")))
	remove_button.visible = true
	_show()

func _show() -> void:
	title_edit.max_length = title_length
	visible = true
	reset_size()
	title_edit.grab_focus.call_deferred()
	title_edit.caret_column = title_edit.text.length()

## Whether it is open.
func is_open() -> bool:
	return visible

## The kind picked.
func get_kind() -> String:
	return str(kind_option.get_item_metadata(kind_option.selected)) if kind_option.selected >= 0 else "pin"

func confirm() -> void:
	if not visible:
		return
	visible = false
	confirmed.emit(title_edit.text.strip_edges(), description_edit.text.strip_edges(), get_kind())

func remove() -> void:
	if not visible:
		return
	visible = false
	removed.emit()

func cancel() -> void:
	if not visible:
		return
	visible = false
	cancelled.emit()
