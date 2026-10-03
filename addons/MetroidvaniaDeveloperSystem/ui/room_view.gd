@tool
class_name IDPRoomView
extends HBoxContainer
## Room view (the "actual view" next to the map view): paint a room scene's terrain,
## background and decorations with brushes or shapes (rectangles, irregular blobs, curved
## sides), or generate a starting cave from the room's shape on the map. Fills come from
## the tileset's terrains and tagged kinds, tiles picked in the palette (spritesheets), or
## solid colors. Saving writes the tiles into the scene; the map's silhouette follows.
##
## Its buttons are in [member controls], a narrow column that Map Dev puts in its left
## tool panel, and Map Dev shows the [member palette] as a tab. Used on its own, the view
## shows the column on its left and the palette on its right.

signal saved(scene_path: String)
signal status_message(text: String)
## The Tile palette button was pressed while the palette lives elsewhere (Map Dev shows it
## as a tab).
signal palette_requested

const DEFAULT_TILESET := "res://idp_tiles/idp_cave_tileset.tres"
const Shape := IDPTerrainShapes.Shape
const TOOL_LAYERS: PackedStringArray = ["Terrain", "Background", "Decor", "Erase", "Foreground", "Freeform", "Stamps"]
const FREEFORM_LAYERS: PackedStringArray = ["Terrain (solid)", "Background", "Foreground"]
const FREEFORM_GROUPS: PackedStringArray = ["Freeform", "FreeformBack", "FreeformFront"]
const STAMP_LAYERS: PackedStringArray = ["Behind terrain", "In front of terrain", "Foreground"]
const STAMP_GROUPS: PackedStringArray = ["StampsBack", "StampsFront", "StampsForeground"]

var canvas: IDPRoomCanvas
var palette: IDPTilePalette
var painter: IDPRoomPainter
var world: IDPWorld
var room_id := ""
var tool_buttons: Array[Button] = []
var fill_opt: OptionButton
var color_button: ColorPickerButton
var brush_spin: SpinBox
var shape_opt: OptionButton
var curve_opt: OptionButton
var count_spin: SpinBox
var rough_spin: SpinBox
var flip_check: CheckBox
var generate_button: Button
var undo_button: Button
var redo_button: Button
## The brush and action buttons, as a column for a side panel.
var controls: VBoxContainer
var _split: HSplitContainer
var _variation := 0
var _filling := false
var layer_opt: OptionButton ## freeform / stamp layer
var mode_opt: OptionButton ## freeform Draw / Edit
var size_spin: SpinBox ## stamp size
var _styles: Array[IDPFreeformStyle] = []
var _stamp_sets: Array[IDPStampSet] = []
var _shape_rows: Array[Control] = []

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls = VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# What to paint.
	var tool_grid := IDPSidePanel.grid(controls, 2)
	var group := ButtonGroup.new()
	var names := ["Terrain", "Background", "Decor", "Erase", "Foreground", "Freeform", "Stamps"]
	var tips := ["Paint the Terrain layer (solid ground: autotiled terrain, palette tiles or colors)", "Paint the Background layer (foliage, palette tiles or a solid color)", "Paint the Decor layer (grass, vines, stalactites, palette tiles...)", "Erase the top item under the brush: a stamp, else foreground, decoration, terrain, then background (palette tiles and colors too). Pick one layer or all layers in the list next to it; Shift erases background only. Works with shapes too, to carve curved caves",
		"Paint the Foreground layer, drawn in front of everything (dark silhouettes framing the room)",
		"Freeform terrain: smooth curvy shapes instead of tiles (rounded ledges, bulging moss walls), with textured edges, clumps and exact collision. Draw by clicking points or dragging freehand, or pick a shape and drag its box. Edit mode reshapes them",
		"Place large clumps freely (moss bubbles, leaves, ferns, hanging moss, background bubbles, foreground silhouettes). Click or drag; Shift removes"]
	for i in names.size():
		var b := IDPUi.button(names[i], tips[i])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.pressed.connect(func() -> void: set_tool(i))
		tool_buttons.append(b)
		tool_grid.add_child(IDPSidePanel.fill(b))
	fill_opt = OptionButton.new()
	fill_opt.fit_to_longest_item = false
	fill_opt.clip_text = true
	fill_opt.tooltip_text = "What the current tool paints: a terrain (autotiled), random tiles of a kind, the tiles picked in the palette, or a solid color"
	fill_opt.item_selected.connect(_on_fill_selected)
	var fill_row := IDPSidePanel.field(controls, "Fill", fill_opt)
	layer_opt = OptionButton.new()
	layer_opt.tooltip_text = "Layer of new freeform shapes or stamps"
	layer_opt.item_selected.connect(_on_layer_selected)
	_shape_rows.append(IDPSidePanel.field(controls, "Layer", layer_opt))
	mode_opt = OptionButton.new()
	mode_opt.add_item("Draw", IDPRoomCanvas.FreeformMode.DRAW)
	mode_opt.add_item("Edit", IDPRoomCanvas.FreeformMode.EDIT)
	mode_opt.tooltip_text = "Draw: click points (or drag freehand) and click the first point, double-click or press Enter to close; or pick a shape below and drag its box.\nEdit: drag points, Alt+click removes one, double-click an edge adds one, drag inside to move, Delete removes the shape."
	mode_opt.item_selected.connect(func(idx: int) -> void:
		canvas.freeform_mode = mode_opt.get_item_id(idx)
		canvas._overlay.queue_redraw())
	_shape_rows.append(IDPSidePanel.field(controls, "Mode", mode_opt))
	size_spin = SpinBox.new()
	size_spin.min_value = 20
	size_spin.max_value = 400
	size_spin.step = 10
	size_spin.value = 100
	size_spin.prefix = "Size"
	size_spin.suffix = "%"
	size_spin.tooltip_text = "Stamp size (each stamp also varies a little)"
	size_spin.value_changed.connect(func(v: float) -> void: canvas.stamp_scale = v / 100.0)
	controls.add_child(IDPSidePanel.fill(size_spin))
	color_button = ColorPickerButton.new()
	color_button.color = Color("#0f2a2c")
	color_button.custom_minimum_size = Vector2(36, 0)
	color_button.tooltip_text = "Solid color painted by the \"Solid color\" fill"
	color_button.visible = false
	color_button.color_changed.connect(func(c: Color) -> void:
		if canvas.fills.get(canvas.tool, {}).get("type", "") == "color":
			canvas.fills[canvas.tool] = {"type": "color", "color": c})
	fill_row.add_child(color_button)
	brush_spin = SpinBox.new()
	brush_spin.min_value = 1
	brush_spin.max_value = 12
	brush_spin.value = 2
	brush_spin.prefix = "Brush"
	brush_spin.tooltip_text = "Brush size in tiles ([ and ] in the view)"
	brush_spin.value_changed.connect(func(v: float) -> void: canvas.brush_size = int(v))
	controls.add_child(IDPSidePanel.fill(brush_spin))
	# Shapes.
	shape_opt = OptionButton.new()
	for i in IDPTerrainShapes.SHAPE_NAMES.size():
		shape_opt.add_item(IDPTerrainShapes.SHAPE_NAMES[i], i)
		shape_opt.set_item_tooltip(i, IDPTerrainShapes.SHAPE_TIPS[i])
	shape_opt.tooltip_text = "Brush or shape. Shapes: drag a box in the view, release to paint it (Esc cancels)"
	shape_opt.item_selected.connect(func(idx: int) -> void:
		canvas.shape = shape_opt.get_item_id(idx)
		_update_shape_controls())
	IDPSidePanel.field(controls, "Shape", shape_opt)
	curve_opt = OptionButton.new()
	curve_opt.fit_to_longest_item = false
	curve_opt.clip_text = true
	for i in IDPTerrainShapes.CURVE_NAMES.size():
		curve_opt.add_item(IDPTerrainShapes.CURVE_NAMES[i], i)
	curve_opt.tooltip_text = "Curve of the curved side: convex bulges out, concave dips in; ramps rise along the side (Flip mirrors them)"
	curve_opt.item_selected.connect(func(idx: int) -> void:
		canvas.curve = curve_opt.get_item_id(idx)
		_update_shape_controls())
	IDPSidePanel.field(controls, "Curve", curve_opt)
	count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 12
	count_spin.value = 3
	count_spin.prefix = "x"
	count_spin.tooltip_text = "Number of waves, steps or spikes"
	count_spin.value_changed.connect(func(v: float) -> void: canvas.curve_count = int(v))
	rough_spin = SpinBox.new()
	rough_spin.min_value = 0
	rough_spin.max_value = 100
	rough_spin.step = 5
	rough_spin.value = 0
	rough_spin.prefix = "Irregular"
	rough_spin.suffix = "%"
	rough_spin.tooltip_text = "How rough and natural the shape's edge is (0 = clean curve)"
	rough_spin.value_changed.connect(func(v: float) -> void: canvas.roughness = v / 100.0)
	controls.add_child(IDPSidePanel.fill(rough_spin))
	flip_check = CheckBox.new()
	flip_check.text = "Flip"
	flip_check.tooltip_text = "Mirror the curve along the side (ramps rise the other way)"
	flip_check.toggled.connect(func(on: bool) -> void: canvas.mirror = on)
	IDPSidePanel.row(controls, [count_spin, flip_check])
	# Actions.
	controls.add_child(HSeparator.new())
	var generation := VBoxContainer.new()
	controls.add_child(generation)
	var actions := IDPSidePanel.grid(controls, 2)
	var gen := IDPUi.button("Generate cave", "Replace the tiles with a cave built from the room's shape on the map: walls, floor, ledges, openings at its gates, background and decorations. Uses the Terrain fill's terrain and the Background fill")
	gen.pressed.connect(func() -> void: generate(false))
	generate_button = gen
	generation.add_child(gen)
	var again := IDPUi.button("New variation", "Generate again with another random layout")
	again.pressed.connect(func() -> void: generate(true))
	generation.add_child(again)
	var deco := IDPUi.button("Auto-decorate", "Redo grass, plants, vines, stalactites and moss on the current terrain (uses tiles tagged with those kinds)")
	deco.pressed.connect(func() -> void:
		if painter:
			painter.checkpoint()
			_variation += 1
			var n := painter.auto_decorate(hash(room_id) + _variation, true, painter.room_cells(world, room_id))
			_changed("Placed %d decorations." % n))
	generation.add_child(deco)
	var back := IDPUi.button("Fill background", "Fill the room's shape with the Background fill (foliage, palette tiles or a solid color)")
	back.pressed.connect(fill_background)
	generation.add_child(back)
	var clear := IDPUi.button("Clear", "Remove all tiles, freeform shapes and stamps")
	clear.pressed.connect(func() -> void:
		if painter:
			painter.checkpoint()
			for n in IDPRoomPainter.LAYER_ORDER:
				painter.clear_layer(n)
			painter.clear_items()
			canvas.selected = null
			_changed("Cleared."))
	actions.add_child(IDPSidePanel.fill(clear))
	undo_button = IDPUi.button("Undo", "Undo the last stroke or shape (Ctrl+Z)")
	undo_button.pressed.connect(func() -> void:
		if painter and painter.undo():
			_changed("Undone."))
	actions.add_child(IDPSidePanel.fill(undo_button))
	redo_button = IDPUi.button("Redo", "Redo (Ctrl+Y)")
	redo_button.pressed.connect(func() -> void:
		if painter and painter.redo():
			_changed("Redone."))
	actions.add_child(IDPSidePanel.fill(redo_button))
	var save_btn := IDPUi.button("Save", "Write the tiles into the room scene")
	save_btn.pressed.connect(save)
	actions.add_child(IDPSidePanel.fill(save_btn))
	var revert := IDPUi.button("Revert", "Reload the scene, dropping unsaved painting")
	revert.pressed.connect(func() -> void:
		if painter:
			painter.dirty = false
			open_room(world, room_id))
	actions.add_child(IDPSidePanel.fill(revert))
	var edit := IDPUi.button("Edit in 2D", "Open the room scene in Godot's editor (saves first)")
	edit.pressed.connect(func() -> void:
		if painter:
			if painter.dirty:
				save()
			EditorInterface.open_scene_from_path(painter.scene_path))
	actions.add_child(IDPSidePanel.fill(edit))
	var palette_toggle := IDPUi.button("Tile palette", "Show the tile palette (spritesheets)")
	palette_toggle.pressed.connect(func() -> void:
		if palette.get_parent() == _split:
			palette.visible = not palette.visible
		else:
			palette_requested.emit())
	actions.add_child(IDPSidePanel.fill(palette_toggle))
	# View and palette.
	_split = HSplitContainer.new()
	_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_split)
	canvas = IDPRoomCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.painted.connect(func() -> void: canvas._overlay.queue_redraw())
	canvas.status_message.connect(func(t: String) -> void: status_message.emit(t))
	_split.add_child(canvas)
	palette = IDPTilePalette.new()
	palette.status_message.connect(func(t: String) -> void: status_message.emit(t))
	palette.selection_changed.connect(_on_palette_picked)
	palette.tileset_changed.connect(func() -> void:
		_fill_pickers(true)
		canvas._overlay.queue_redraw())
	_update_shape_controls()
	_update_tool_controls()

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
	var tiles_path := str(world.get_setting("room_tileset", ""))
	var tiles := IDPTilesetFactory.get_or_create(tiles_path if not tiles_path.is_empty() else DEFAULT_TILESET)
	var moved := IDPRoomPainter.externalize_sheets(tiles) if tiles else 0
	if moved > 0:
		status_message.emit("Moved %d sheet image(s) embedded in %s out to PNG files next to it, so the tileset loads fast." % [moved, tiles.resource_path.get_file()])
	painter = IDPRoomPainter.open(path, tiles)
	if not painter:
		return "Could not open %s." % path
	canvas.open(world, id, painter)
	palette.set_painter(painter)
	_load_styles()
	_fill_pickers(true)
	# Generate cave builds autotiled terrain.
	generate_button.disabled = not painter.has_terrains()
	if not painter.has_terrains():
		status_message.emit("%s's tileset has no terrains, so Generate cave is off. Paint with palette tiles, or make a terrain from a 3x3 block in the palette." % id)
	_fit_later()
	return ""

func _ready() -> void:
	_adopt_controls.call_deferred()

## Used on its own (not in Map Dev), the button column goes on the left of the view and
## the palette on its right.
func _adopt_controls() -> void:
	if palette and not palette.get_parent():
		_split.add_child(palette)
	if controls and not controls.get_parent():
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.x = IDPSidePanel.WIDTH * IDPUi.editor_scale()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(controls)
		add_child(scroll)
		move_child(scroll, 0)

func _fit_later() -> void:
	await get_tree().process_frame
	canvas.fit()

func _notification(what: int) -> void:
	# Panel going away with a room open: the displayed layers go with the tree, but the
	# off-tree scene instance must be freed here.
	if what == NOTIFICATION_PREDELETE:
		if painter and is_instance_valid(painter.root):
			painter.root.free()
		if is_instance_valid(controls) and not controls.get_parent():
			controls.free()
		if is_instance_valid(palette) and not palette.get_parent():
			palette.free()

func close_room(auto_save := true) -> void:
	if painter and painter.dirty and auto_save:
		save()
	canvas.close()
	if painter:
		painter.free_instance()
	painter = null
	palette.set_painter(null)

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

func set_tool(t: int) -> void:
	canvas.tool = t
	tool_buttons[t].set_pressed_no_signal(true)
	_fill_pickers(false)
	_update_tool_controls()
	canvas._overlay.queue_redraw()
	canvas.grab_focus()

## Shows the controls the current tool uses.
func _update_tool_controls() -> void:
	var t := canvas.tool
	var freeform := t == IDPRoomCanvas.Tool.FREEFORM
	var stamps := t == IDPRoomCanvas.Tool.STAMP
	layer_opt.get_parent().visible = freeform or stamps
	mode_opt.get_parent().visible = freeform
	size_spin.visible = stamps
	brush_spin.visible = not freeform and not stamps
	shape_opt.get_parent().visible = not stamps
	curve_opt.get_parent().visible = not stamps
	rough_spin.visible = not stamps
	flip_check.get_parent().visible = not stamps
	_filling = true
	layer_opt.clear()
	if freeform:
		for i in FREEFORM_LAYERS.size():
			layer_opt.add_item(FREEFORM_LAYERS[i], i)
		layer_opt.select(maxi(0, FREEFORM_GROUPS.find(canvas.freeform_group)))
	elif stamps:
		for i in STAMP_LAYERS.size():
			layer_opt.add_item(STAMP_LAYERS[i], i)
		layer_opt.select(maxi(0, STAMP_GROUPS.find(canvas.stamp_group)))
	_filling = false

func _on_layer_selected(idx: int) -> void:
	if _filling:
		return
	if canvas.tool == IDPRoomCanvas.Tool.FREEFORM:
		canvas.freeform_group = FREEFORM_GROUPS[idx]
		canvas.freeform_solid = idx == 0
		if is_instance_valid(canvas.selected) and painter and canvas.freeform_mode == IDPRoomCanvas.FreeformMode.EDIT:
			# Edit mode: move the selected shape to that layer.
			painter.checkpoint()
			var node := canvas.selected
			node.get_parent().remove_child(node)
			node.solid = canvas.freeform_solid
			painter.items_root.get_node(canvas.freeform_group).add_child(node)
			painter.dirty = true
	elif canvas.tool == IDPRoomCanvas.Tool.STAMP:
		canvas.stamp_group = STAMP_GROUPS[idx]

func generate(new_variation: bool) -> void:
	if not painter or not painter.has_terrains():
		return
	if new_variation:
		_variation += 1
	var terrain := _terrain_for_generation()
	painter.checkpoint()
	painter.generate_cave(world, room_id, hash(room_id) + _variation * 7919, terrain.x, terrain.y, canvas.fills.get(IDPRoomCanvas.Tool.BACKGROUND, {}))
	_changed("Generated a cave from %s's shape on the map (%d gates kept open). Paint over it, then Save." % [room_id, world.get_gates(room_id).size()])

func fill_background() -> void:
	if not painter:
		return
	painter.checkpoint()
	painter.clear_layer("Background")
	painter.paint_fill("Background", painter.room_cells(world, room_id).keys(), canvas.fills[IDPRoomCanvas.Tool.BACKGROUND])
	_changed("Background filled.")

func _terrain_for_generation() -> Vector2i:
	var f: Dictionary = canvas.fills.get(IDPRoomCanvas.Tool.TERRAIN, {})
	if f.get("type", "") == "terrain":
		return Vector2i(f["set"], f.terrain)
	var t: Array = painter.get_terrains()[0]
	return Vector2i(t[0], t[1])

func _changed(message: String) -> void:
	canvas._overlay.queue_redraw()
	status_message.emit(message)

func _update_shape_controls() -> void:
	var curved := IDPTerrainShapes.is_curved(canvas.shape)
	curve_opt.disabled = not curved
	flip_check.disabled = not curved
	count_spin.editable = curved and canvas.curve in [IDPTerrainShapes.CurveType.WAVE, IDPTerrainShapes.CurveType.STEPS, IDPTerrainShapes.CurveType.SPIKES]
	rough_spin.editable = canvas.shape != Shape.BRUSH and canvas.shape != Shape.RECT
	brush_spin.editable = canvas.shape == Shape.BRUSH

# --- Fills ---------------------------------------------------------------------------------------

## Fills the current tool can use, as [text, icon, fill].
func _fill_choices() -> Array:
	var out: Array = []
	for t in painter.get_terrains():
		var tname := str(t[2]) if not str(t[2]).is_empty() else "Terrain %d/%d" % [t[0], t[1]]
		out.append(["Terrain: %s" % tname, IDPUi.color_icon(painter.tile_set.get_terrain_color(t[0], t[1])), {"type": "terrain", "set": t[0], "terrain": t[1]}])
	var kinds := painter.get_decor_tiles()
	for kind in kinds:
		var tile: Array = kinds[kind][0]
		var src := painter.tile_set.get_source(tile[0]) as TileSetAtlasSource
		var icon := AtlasTexture.new()
		icon.atlas = src.texture
		icon.region = src.get_tile_texture_region(tile[1])
		out.append(["%s (random)" % str(kind).capitalize(), icon, {"type": "kind", "kind": kind}])
	out.append(["Palette tiles (%s)" % palette.describe_fill(), null, {"type": "stamp"}])
	out.append(["Solid color", IDPUi.color_icon(color_button.color), {"type": "color"}])
	return out

func _default_fill(t: int, choices: Array) -> Dictionary:
	var want := ""
	match t:
		IDPRoomCanvas.Tool.TERRAIN:
			want = "terrain"
		IDPRoomCanvas.Tool.BACKGROUND:
			for c in choices:
				if c[2].get("kind", "") == "foliage":
					return c[2]
			return {"type": "color", "color": color_button.color}
		IDPRoomCanvas.Tool.DECOR:
			for c in choices:
				if c[2].get("type") == "kind" and c[2].kind != "foliage":
					return c[2]
		IDPRoomCanvas.Tool.FOREGROUND:
			return {"type": "color", "color": Color("#03070a")}
	for c in choices:
		if c[2].get("type") == want:
			return c[2]
	return {"type": "color", "color": color_button.color}

func _same_fill(a: Dictionary, b: Dictionary) -> bool:
	if a.get("type") != b.get("type"):
		return false
	match str(a.get("type")):
		"terrain":
			return a["set"] == b["set"] and a.terrain == b.terrain
		"kind":
			return a.kind == b.kind
	return true

func _fill_valid(f: Dictionary, choices: Array) -> bool:
	if f.get("type") == "stamp":
		return painter.tile_set.has_source(int(f.get("source", -1)))
	if f.get("type") == "color":
		return true
	for c in choices:
		if _same_fill(c[2], f):
			return true
	return false

## Rebuilds the fill list for the current tool. With [param validate], fills that no
## longer exist in the tileset fall back to defaults.
func _fill_pickers(validate: bool) -> void:
	if not painter:
		return
	var choices := _fill_choices()
	if validate:
		for t in [IDPRoomCanvas.Tool.TERRAIN, IDPRoomCanvas.Tool.BACKGROUND, IDPRoomCanvas.Tool.DECOR, IDPRoomCanvas.Tool.FOREGROUND]:
			if not _fill_valid(canvas.fills.get(t, {}), choices):
				canvas.fills[t] = _default_fill(t, choices)
	_filling = true
	fill_opt.clear()
	var erase := canvas.tool == IDPRoomCanvas.Tool.ERASE
	fill_opt.disabled = false
	if canvas.tool == IDPRoomCanvas.Tool.FREEFORM:
		for i in _styles.size():
			fill_opt.add_item(_styles[i].get_display_name(), i)
		fill_opt.select(maxi(0, _styles.find(canvas.freeform_style)))
		fill_opt.tooltip_text = "Style of new freeform shapes (and of the selected one). Styles are *.freeform.tres files in the project"
		color_button.visible = false
		_filling = false
		return
	if canvas.tool == IDPRoomCanvas.Tool.STAMP:
		var k := 0
		for si in _stamp_sets.size():
			for cat in _stamp_sets[si].get_categories():
				fill_opt.add_item("%s: %s" % [_stamp_sets[si].get_display_name(), cat.capitalize()], k)
				fill_opt.set_item_metadata(fill_opt.item_count - 1, [si, cat])
				if _stamp_sets[si] == canvas.stamp_set and cat == canvas.stamp_category:
					fill_opt.select(fill_opt.item_count - 1)
				k += 1
		if fill_opt.item_count == 0:
			fill_opt.add_item("No stamp sets (add the Mossgrove pack)")
		fill_opt.tooltip_text = "Stamps placed by the brush. Stamp sets are *.stamps.tres files in the project"
		color_button.visible = false
		_filling = false
		return
	if erase:
		# The list chooses what Erase removes.
		for i in IDPRoomCanvas.ERASE_MODE_NAMES.size():
			fill_opt.add_item(IDPRoomCanvas.ERASE_MODE_NAMES[i], i)
		fill_opt.select(canvas.erase_mode)
		fill_opt.tooltip_text = "What Erase removes (Shift: background only)"
		color_button.visible = false
		_filling = false
		return
	fill_opt.tooltip_text = "What the current tool paints: a terrain (autotiled), random tiles of a kind, the tiles picked in the palette, or a solid color"
	var current: Dictionary = canvas.fills.get(canvas.tool, {})
	for c in choices:
		if c[1]:
			fill_opt.add_icon_item(c[1], c[0])
		else:
			fill_opt.add_item(c[0])
		fill_opt.set_item_metadata(fill_opt.item_count - 1, c[2])
		if not erase and _same_fill(c[2], current):
			fill_opt.select(fill_opt.item_count - 1)
	color_button.visible = not erase and current.get("type") == "color"
	if color_button.visible:
		color_button.color = current.get("color", color_button.color)
	_filling = false

func _on_fill_selected(idx: int) -> void:
	if _filling:
		return
	if canvas.tool == IDPRoomCanvas.Tool.ERASE:
		canvas.erase_mode = fill_opt.get_item_id(idx)
		return
	if canvas.tool == IDPRoomCanvas.Tool.FREEFORM:
		_set_freeform_style(_styles[fill_opt.get_item_id(idx)], true)
		return
	if canvas.tool == IDPRoomCanvas.Tool.STAMP:
		var meta: Variant = fill_opt.get_item_metadata(idx)
		if meta is Array:
			canvas.stamp_set = _stamp_sets[meta[0]]
			canvas.stamp_category = meta[1]
		return
	var f: Dictionary = fill_opt.get_item_metadata(idx)
	match str(f.type):
		"stamp":
			if not palette.has_selection():
				status_message.emit("Pick tiles in the palette first (drag over them), or add a spritesheet with + Sheet.")
				_fill_pickers(false)
				return
			f = palette.get_fill()
		"color":
			f = {"type": "color", "color": color_button.color}
	canvas.fills[canvas.tool] = f
	color_button.visible = f.type == "color"

## Picks a freeform style; its default layer is used for new shapes. With
## [param apply_to_selected] in Edit mode, the selected shape takes the style too.
func _set_freeform_style(st: IDPFreeformStyle, apply_to_selected: bool) -> void:
	canvas.freeform_style = st
	var idx := {"terrain": 0, "back": 1, "front": 2}.get(st.default_layer, 0)
	canvas.freeform_group = FREEFORM_GROUPS[idx]
	canvas.freeform_solid = st.solid and idx == 0
	if apply_to_selected and is_instance_valid(canvas.selected) and painter and canvas.freeform_mode == IDPRoomCanvas.FreeformMode.EDIT:
		painter.checkpoint()
		canvas.selected.style = st
		painter.dirty = true
	_update_tool_controls()

## Freeform styles and stamp sets available: built-ins plus the project's files.
func _load_styles() -> void:
	_styles = IDPFreeformStyle.builtins()
	_styles.append_array(IDPFreeformStyle.find_in_project())
	_stamp_sets = IDPStampSet.find_in_project()
	if not canvas.freeform_style or not canvas.freeform_style in _styles:
		# Prefer a textured style from the project (a mossy one if there is).
		var pick := _styles[0]
		for st in _styles.slice(3):
			if pick == _styles[0] or st.get_display_name().to_lower().contains("moss"):
				pick = st
		_set_freeform_style(pick, false)
	if (not canvas.stamp_set or not canvas.stamp_set in _stamp_sets) and not _stamp_sets.is_empty():
		canvas.stamp_set = _stamp_sets[0]
		var cats := canvas.stamp_set.get_categories()
		canvas.stamp_category = cats[0] if not cats.is_empty() else ""

## Tiles picked in the palette: the current tool paints them (Erase, Freeform and Stamps
## switch to Terrain).
func _on_palette_picked() -> void:
	if not palette.has_selection():
		return
	if canvas.tool in [IDPRoomCanvas.Tool.ERASE, IDPRoomCanvas.Tool.FREEFORM, IDPRoomCanvas.Tool.STAMP]:
		set_tool(IDPRoomCanvas.Tool.TERRAIN)
	canvas.fills[canvas.tool] = palette.get_fill()
	_fill_pickers(false)
	status_message.emit("%s brush paints the palette tiles (%s)." % [TOOL_LAYERS[canvas.tool], palette.describe_fill()])
