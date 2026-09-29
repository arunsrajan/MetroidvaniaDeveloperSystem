@tool
class_name IDPRoomView
extends VBoxContainer
## Room view (the "actual view" next to the map view): paint a room scene's terrain,
## background and decorations with brushes, or generate a starting cave from the room's
## shape on the map. Saving writes the tiles into the scene; the map's silhouette follows.

signal saved(scene_path: String)
signal status_message(text: String)

const DEFAULT_TILESET := "res://idp_tiles/idp_cave_tileset.tres"

var canvas: IDPRoomCanvas
var painter: IDPRoomPainter
var world: IDPWorld
var room_id := ""
var tool_buttons: Array[Button] = []
var terrain_opt: OptionButton
var decor_opt: OptionButton
var brush_spin: SpinBox
var generate_button: Button
var _variation := 0

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HFlowContainer.new()
	add_child(bar)
	var group := ButtonGroup.new()
	var names := ["Terrain", "Background", "Decor", "Erase"]
	var tips := ["Paint terrain (autotiled rock)", "Paint background foliage", "Place decorations (grass, vines, stalactites...)", "Erase decorations and terrain (Shift: background)"]
	for i in names.size():
		var b := IDPUi.button(names[i], tips[i])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.pressed.connect(func() -> void:
			canvas.tool = i
			canvas.grab_focus())
		tool_buttons.append(b)
		bar.add_child(b)
	terrain_opt = OptionButton.new()
	terrain_opt.tooltip_text = "Terrain painted by the Terrain brush"
	terrain_opt.item_selected.connect(func(idx: int) -> void: canvas.terrain_pick = terrain_opt.get_item_metadata(idx))
	bar.add_child(terrain_opt)
	decor_opt = OptionButton.new()
	decor_opt.tooltip_text = "Decoration placed by the Decor brush"
	decor_opt.item_selected.connect(func(idx: int) -> void:
		canvas.decor_kind = decor_opt.get_item_metadata(idx)
		tool_buttons[IDPRoomCanvas.Tool.DECOR].button_pressed = true
		canvas.tool = IDPRoomCanvas.Tool.DECOR)
	bar.add_child(decor_opt)
	brush_spin = SpinBox.new()
	brush_spin.min_value = 1
	brush_spin.max_value = 12
	brush_spin.value = 2
	brush_spin.prefix = "Brush"
	brush_spin.value_changed.connect(func(v: float) -> void: canvas.brush_size = int(v))
	bar.add_child(brush_spin)
	bar.add_child(VSeparator.new())
	var gen := IDPUi.button("Generate cave", "Replace the tiles with a cave built from the room's shape on the map: walls, floor, ledges, openings at its gates, background and decorations")
	gen.pressed.connect(func() -> void: generate(false))
	generate_button = gen
	bar.add_child(gen)
	var again := IDPUi.button("New variation", "Generate again with another random layout")
	again.pressed.connect(func() -> void: generate(true))
	bar.add_child(again)
	var deco := IDPUi.button("Auto-decorate", "Redo grass, plants, vines, stalactites and moss on the current terrain")
	deco.pressed.connect(func() -> void:
		if painter:
			_variation += 1
			var n := painter.auto_decorate(hash(room_id) + _variation, true, painter.room_cells(world, room_id))
			_changed("Placed %d decorations." % n))
	bar.add_child(deco)
	var back := IDPUi.button("Fill background", "Fill the room's shape with background foliage")
	back.pressed.connect(func() -> void:
		if painter:
			painter.clear_layer("Background")
			painter.place_kind("Background", painter.room_cells(world, room_id).keys(), "foliage")
			_changed("Background filled."))
	bar.add_child(back)
	var clear := IDPUi.button("Clear", "Remove all tiles from the three layers")
	clear.pressed.connect(func() -> void:
		if painter:
			for n in IDPRoomPainter.LAYER_ORDER:
				painter.clear_layer(n)
			_changed("Cleared."))
	bar.add_child(clear)
	bar.add_child(VSeparator.new())
	var save_btn := IDPUi.button("Save", "Write the tiles into the room scene")
	save_btn.pressed.connect(save)
	bar.add_child(save_btn)
	var revert := IDPUi.button("Revert", "Reload the scene, dropping unsaved painting")
	revert.pressed.connect(func() -> void:
		if painter:
			painter.dirty = false
			open_room(world, room_id))
	bar.add_child(revert)
	var edit := IDPUi.button("Open in 2D editor", "Open the room scene in Godot's editor (saves first)")
	edit.pressed.connect(func() -> void:
		if painter:
			if painter.dirty:
				save()
			EditorInterface.open_scene_from_path(painter.scene_path))
	bar.add_child(edit)
	canvas = IDPRoomCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.painted.connect(func() -> void: canvas._overlay.queue_redraw())
	canvas.status_message.connect(func(t: String) -> void: status_message.emit(t))
	add_child(canvas)

## Opens the room for painting. Returns an error message, or "" on success.
func open_room(p_world: IDPWorld, id: String) -> String:
	if painter and painter.dirty:
		save()
	close_room(false)
	world = p_world
	room_id = id
	var path := world.get_scene_path(id)
	if path.is_empty():
		return "%s has no scene." % id
	var tiles := IDPTilesetFactory.get_or_create(str(world.get_setting("room_tileset", DEFAULT_TILESET)))
	painter = IDPRoomPainter.open(path, tiles)
	if not painter:
		return "Could not open %s." % path
	canvas.open(world, id, painter)
	_fill_pickers()
	# Terrain painting needs a tileset with terrains (autotiling).
	var terrains := painter.has_terrains()
	tool_buttons[IDPRoomCanvas.Tool.TERRAIN].disabled = not terrains
	generate_button.disabled = not terrains
	terrain_opt.disabled = not terrains
	if not terrains:
		canvas.tool = IDPRoomCanvas.Tool.DECOR
		tool_buttons[IDPRoomCanvas.Tool.DECOR].button_pressed = true
		status_message.emit("%s's tileset has no terrains, so terrain painting and Generate cave are off. Set up terrains in the TileSet, or use Decor/Erase." % id)
	_fit_later()
	return ""

func _fit_later() -> void:
	await get_tree().process_frame
	canvas.fit()

func _notification(what: int) -> void:
	# Panel going away with a room open: the displayed layers go with the tree, but the
	# off-tree scene instance must be freed here.
	if what == NOTIFICATION_PREDELETE and painter and is_instance_valid(painter.root):
		painter.root.free()

func close_room(auto_save := true) -> void:
	if painter and painter.dirty and auto_save:
		save()
	canvas.close()
	if painter:
		painter.free_instance()
	painter = null

func save() -> Error:
	if not painter:
		return ERR_UNCONFIGURED
	var err := painter.save()
	if err == OK:
		saved.emit(painter.scene_path)
		status_message.emit("Saved %s." % painter.scene_path.get_file())
	else:
		status_message.emit("Could not save %s (error %d)." % [painter.scene_path, err])
	canvas._overlay.queue_redraw()
	return err

func generate(new_variation: bool) -> void:
	if not painter:
		return
	if new_variation:
		_variation += 1
	painter.generate_cave(world, room_id, hash(room_id) + _variation * 7919, canvas.terrain_pick.x, canvas.terrain_pick.y)
	_changed("Generated a cave from %s's shape on the map (%d gates kept open). Paint over it, then Save." % [room_id, world.get_gates(room_id).size()])

func _changed(message: String) -> void:
	canvas._overlay.queue_redraw()
	status_message.emit(message)

func _fill_pickers() -> void:
	terrain_opt.clear()
	var terrains := painter.get_terrains()
	for t in terrains:
		terrain_opt.add_item(t[2] if not str(t[2]).is_empty() else "Terrain %d/%d" % [t[0], t[1]])
		terrain_opt.set_item_metadata(terrain_opt.item_count - 1, Vector2i(t[0], t[1]))
	if terrain_opt.item_count > 0:
		terrain_opt.select(0)
		canvas.terrain_pick = terrain_opt.get_item_metadata(0)
	decor_opt.clear()
	var kinds := painter.get_decor_tiles()
	for kind in kinds:
		if kind == "foliage":
			continue
		var t: Array = kinds[kind][0]
		var src := painter.tile_set.get_source(t[0]) as TileSetAtlasSource
		var icon := AtlasTexture.new()
		icon.atlas = src.texture
		icon.region = src.get_tile_texture_region(t[1])
		decor_opt.add_icon_item(icon, str(kind).capitalize())
		decor_opt.set_item_metadata(decor_opt.item_count - 1, kind)
	if decor_opt.item_count > 0:
		decor_opt.select(0)
		canvas.decor_kind = decor_opt.get_item_metadata(0)
