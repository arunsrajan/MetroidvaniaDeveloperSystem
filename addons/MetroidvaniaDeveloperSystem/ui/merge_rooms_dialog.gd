@tool
class_name MDSMergeRoomsDialog
extends ConfirmationDialog
## Merge rooms: the rooms picked on the map (an area's, or those selected together) become one
## room (see [method MDSWorld.merge_rooms]), and then, as picked here: what was painted in their
## scenes comes into its scene, a cave is generated for it (keeping walls where the old rooms
## met, with openings at their doors), a variation of it, and it opens in the Room view.

## Merge asked for: [param ids] into [param keep], [param options] {content, generate, walls,
## variation, open}.
signal merge_requested(ids: Array[String], keep: String, options: Dictionary)

var world: MDSWorld
var ids: Array[String] = []

var _text: Label
var _keep: OptionButton
var _content: CheckBox
var _generate: CheckBox
var _walls: CheckBox
var _variation: SpinBox
var _open: CheckBox

func _init() -> void:
	title = "Merge rooms"
	ok_button_text = "Merge"
	var box := VBoxContainer.new()
	_text = MDSUi.hint("")
	_text.custom_minimum_size.x = 420
	box.add_child(_text)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(MDSUi.label("Keep"))
	_keep = OptionButton.new()
	_keep.tooltip_text = "The room that stays: its id, its place in the map's order, its scene and its settings (names, notes and abilities it lacks come from the others). The others' gates to the rest of the map are renamed where their names are taken"
	grid.add_child(_keep)
	_content = CheckBox.new()
	_content.text = "Bring what is painted in their scenes into its scene"
	_content.tooltip_text = "Their tiles (only inside their own room; the walls where they meet drawn as one again), freeform shapes, stamps, effects, pictures and other nodes (enemies, pickups...) go into the kept room's scene, where they were on the map. Tiles of another tileset or off its grid come as free tile pieces. Their gate nodes and map guides are made anew. Their scenes stay on disk, no longer used"
	_content.button_pressed = true
	box.add_child(_content)
	_generate = CheckBox.new()
	_generate.text = "Generate a cave for the merged room"
	_generate.tooltip_text = "Replace its tiles with a cave built from its shape on the map, with the Room view's fills and Generate options (saved; Ctrl+Z on the map undoes the merge, not the scene)"
	box.add_child(_generate)
	var row := HBoxContainer.new()
	_walls = CheckBox.new()
	_walls.text = "Walls where the old rooms met"
	_walls.tooltip_text = "The cave keeps walls where the merged rooms met, with openings where their doors were, each old room reached through them. Off: one open cave"
	_walls.button_pressed = true
	row.add_child(_walls)
	row.add_child(MDSUi.label("Variation"))
	_variation = SpinBox.new()
	_variation.max_value = 99999
	_variation.tooltip_text = "Another number, another cave (the Room view's New variation gives more)"
	row.add_child(_variation)
	var again := MDSUi.button("New", "Another variation")
	again.pressed.connect(func() -> void: _variation.value = randi() % 100000)
	row.add_child(again)
	box.add_child(row)
	_generate.toggled.connect(func(on: bool) -> void:
		_walls.disabled = not on
		_variation.editable = on)
	_walls.disabled = true
	_variation.editable = false
	_open = CheckBox.new()
	_open.text = "Open it in the Room view"
	_open.tooltip_text = "Edit the merged room: Generate cave and New variation there too"
	_open.button_pressed = true
	box.add_child(_open)
	MDSUi.scroll_content(self, box)
	confirmed.connect(func() -> void:
		merge_requested.emit(ids, _keep.get_item_text(_keep.selected), options()))

## Asks about merging [param p_ids] of [param p_world] ([param keep]: the one to keep, the first
## by default). [param label] names them ("area Caves", "3 rooms").
func open(p_world: MDSWorld, p_ids: Array[String], keep := "", label := "") -> void:
	world = p_world
	ids = p_ids.duplicate()
	_keep.clear()
	for id in ids:
		_keep.add_item(id)
	_keep.select(maxi(0, ids.find(keep)))
	var scenes := 0
	for id in ids:
		if not world.get_scene_path(id).is_empty():
			scenes += 1
	_content.disabled = scenes == 0
	var error := world.merge_error(ids, keep)
	_text.text = error if not error.is_empty() else "Merge %s (%s) into one room? The gates between them go: their doors stay as openings between its parts. Everything that led to them leads to it. Ctrl+Z on the map takes it back (scene files changed by the options below stay as they are)." % [label if not label.is_empty() else "%d rooms" % ids.size(), ", ".join(ids)]
	get_ok_button().disabled = not error.is_empty()
	MDSUi.popup_fitted(self, 480)

## The options picked: {content, generate, walls, variation, open}.
func options() -> Dictionary:
	return {"content": _content.button_pressed and not _content.disabled, "generate": _generate.button_pressed,
		"walls": _walls.button_pressed, "variation": int(_variation.value), "open": _open.button_pressed}
