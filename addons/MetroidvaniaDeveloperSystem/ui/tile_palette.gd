@tool
class_name MDSTilePalette
extends VBoxContainer
## Tile palette of the Room view: the room tileset's spritesheets, with tiles to pick for
## the Terrain, Background and Decor brushes. Add spritesheets (PNG...), then drag over
## tiles to select one or a block; the brushes paint the selection as a repeating pattern
## (or random tiles from it). The selection can also be made solid, tagged as a kind for
## Auto-decorate, or turned into an autotiling terrain (3x3 box or 4x4 sides layout).

signal selection_changed ## the picked tiles changed (see [method get_fill])
signal tileset_changed ## terrains, kinds or sheets changed
signal status_message(text: String)

const KNOWN_KINDS: PackedStringArray = ["foliage", "grass", "fern", "flower", "mushroom", "vine_top", "vine_mid", "vine_end", "stalactite_small", "stalactite_large", "hanging_moss"]

var painter: MDSRoomPainter
var source_id := -1
var selection := Rect2i() ## atlas coords
var zoom := 1.0

var source_opt: OptionButton
var random_check: CheckBox
var info: Label
var grid: Control
var scroll: ScrollContainer
var terrain_name: LineEdit
var kind_edit: LineEdit
var _drag_from := Vector2i(-1, -1)
var _file_dialog: EditorFileDialog
var _import_dialog: ConfirmationDialog
var _import_path := ""
var _import_fields: Dictionary = {}

func _init() -> void:
	custom_minimum_size.x = 230 * MDSUi.editor_scale()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(MDSUi.title("Tile palette"))
	var row := HBoxContainer.new()
	add_child(row)
	source_opt = OptionButton.new()
	source_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_opt.fit_to_longest_item = false
	source_opt.clip_text = true
	source_opt.tooltip_text = "Spritesheet shown below"
	source_opt.item_selected.connect(func(idx: int) -> void: show_source(source_opt.get_item_id(idx)))
	row.add_child(source_opt)
	var add := MDSUi.button("+ Sheet", "Add a spritesheet (PNG, WebP, JPG...) to the room tileset")
	add.pressed.connect(_pick_sheet)
	row.add_child(add)
	var tools := HBoxContainer.new()
	add_child(tools)
	var zoom_out := MDSUi.button("-", "Zoom out")
	zoom_out.pressed.connect(func() -> void: set_zoom(zoom / 1.5))
	tools.add_child(zoom_out)
	var zoom_in := MDSUi.button("+", "Zoom in")
	zoom_in.pressed.connect(func() -> void: set_zoom(zoom * 1.5))
	tools.add_child(zoom_in)
	random_check = CheckBox.new()
	random_check.text = "Random"
	random_check.tooltip_text = "Paint a random tile of the selection per cell (scatter) instead of repeating it as a pattern"
	random_check.toggled.connect(func(_on: bool) -> void: selection_changed.emit())
	tools.add_child(random_check)
	var remove := MDSUi.button("Remove", "Remove this spritesheet from the tileset (tiles painted from it disappear)")
	remove.pressed.connect(func() -> void:
		if painter and source_id >= 0:
			painter.remove_sheet(source_id)
			refresh()
			tileset_changed.emit())
	tools.add_child(remove)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 160
	add_child(scroll)
	grid = Control.new()
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.draw.connect(_draw_grid)
	grid.gui_input.connect(_grid_input)
	scroll.add_child(grid)
	# Only the visible part of the sheet is drawn: redraw when it scrolls or resizes.
	scroll.get_h_scroll_bar().value_changed.connect(func(_v: float) -> void: grid.queue_redraw())
	scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: grid.queue_redraw())
	scroll.resized.connect(grid.queue_redraw)
	info = MDSUi.hint("Drag over tiles to pick them for the brushes.")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	# Selection actions.
	var solid := MDSUi.button("Solid on/off", "Give the selected tiles full-tile collision (walkable ground), or remove it")
	solid.pressed.connect(_toggle_solid)
	add_child(solid)
	var terrain_row := HBoxContainer.new()
	add_child(terrain_row)
	terrain_name = LineEdit.new()
	terrain_name.placeholder_text = "Terrain name"
	terrain_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_row.add_child(terrain_name)
	var make := MDSUi.button("Make terrain", "Turn the selection into an autotiling terrain (solid). Select a 3x3 box (corners, edges, fill) or 4x4 tiles ordered by connected sides (1 right + 2 bottom + 4 left + 8 top)")
	make.pressed.connect(_make_terrain)
	terrain_row.add_child(make)
	var kind_row := HBoxContainer.new()
	add_child(kind_row)
	kind_edit = LineEdit.new()
	kind_edit.placeholder_text = "Kind, e.g. grass"
	kind_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind_row.add_child(kind_edit)
	var kinds := MDSUi.menu_button("v", "Kinds used by Auto-decorate and Generate cave (foliage = background)")
	for k in KNOWN_KINDS:
		kinds.get_popup().add_item(k)
	kinds.get_popup().index_pressed.connect(func(i: int) -> void: kind_edit.text = KNOWN_KINDS[i])
	kind_row.add_child(kinds)
	var tag := MDSUi.button("Tag", "Tag the selected tiles with this kind (empty: remove the tag). Tagged tiles show up in the brush fills and are used by Auto-decorate")
	tag.pressed.connect(_tag)
	kind_row.add_child(tag)

func set_painter(p: MDSRoomPainter) -> void:
	painter = p
	refresh()

## Rebuilds the sheet list, keeping the shown sheet when it still exists.
func refresh() -> void:
	source_opt.clear()
	if not painter:
		source_id = -1
		grid.queue_redraw()
		return
	var keep := source_id
	source_id = -1
	for s in painter.get_atlas_sources():
		source_opt.add_item(s[1], s[0])
	if source_opt.item_count == 0:
		info.text = "No spritesheets yet. Press + Sheet to add one."
		grid.custom_minimum_size = Vector2.ZERO
		grid.queue_redraw()
		return
	var idx := source_opt.get_item_index(keep)
	show_source(keep if idx >= 0 else source_opt.get_item_id(0))

func show_source(id: int) -> void:
	if id != source_id:
		selection = Rect2i()
	source_id = id
	source_opt.select(source_opt.get_item_index(id))
	var src := _source()
	if src and zoom == 1.0:
		# Fit wide sheets to the panel.
		var w := float(src.texture.get_width())
		zoom = clampf((maxf(size.x, custom_minimum_size.x) - 16.0) / w, 0.25, 4.0) if w > 0 else 1.0
	set_zoom(zoom)
	_update_info()

func set_zoom(value: float) -> void:
	zoom = clampf(value, 0.25, 8.0)
	var src := _source()
	grid.custom_minimum_size = Vector2(src.texture.get_size()) * zoom if src else Vector2.ZERO
	grid.queue_redraw()

func _source() -> TileSetAtlasSource:
	if not painter or source_id < 0 or not painter.tile_set.has_source(source_id):
		return null
	return painter.tile_set.get_source(source_id) as TileSetAtlasSource

func has_selection() -> bool:
	return _source() != null and selection.has_area()

## The brush fill for the picked tiles ({} when nothing is picked).
func get_fill() -> Dictionary:
	if not has_selection():
		return {}
	return {"type": "stamp", "source": source_id, "region": selection, "random": random_check.button_pressed}

func describe_fill() -> String:
	return "%s %dx%d%s" % [source_opt.get_item_text(source_opt.selected), selection.size.x, selection.size.y, " random" if random_check.button_pressed else ""] if has_selection() else "nothing picked"

## Picks tiles by atlas coords (also used by tests).
func select_region(region: Rect2i) -> void:
	selection = region
	grid.queue_redraw()
	_update_info()
	selection_changed.emit()

# --- Grid ------------------------------------------------------------------------------------

func _tile_rect(src: TileSetAtlasSource, coords: Vector2i) -> Rect2:
	var r := src.get_tile_texture_region(coords) if src.has_tile(coords) else Rect2i(src.margins + coords * (src.texture_region_size + src.separation), src.texture_region_size)
	return Rect2(Vector2(r.position) * zoom, Vector2(r.size) * zoom)

func _coords_at(pos: Vector2) -> Vector2i:
	var src := _source()
	if not src:
		return Vector2i(-1, -1)
	var step := Vector2(src.texture_region_size + src.separation) * zoom
	var c := Vector2i(((pos - Vector2(src.margins) * zoom) / step).floor())
	var grid_size := src.get_atlas_grid_size()
	return c.clamp(Vector2i.ZERO, grid_size - Vector2i.ONE)

## Draws the sheet, its grid and tile markers. Only the part visible in the scroll area is
## drawn: big sheets have thousands of tiles, and drawing them all (an outline each)
## stalls the editor for seconds on every redraw.
func _draw_grid() -> void:
	var src := _source()
	if not src:
		return
	var full := Rect2(Vector2.ZERO, grid.custom_minimum_size)
	var view := Rect2(Vector2(scroll.scroll_horizontal, scroll.scroll_vertical), scroll.size).intersection(full)
	if not view.has_area():
		view = full
	grid.draw_rect(view, Color(0.1, 0.1, 0.12))
	grid.draw_texture_rect(src.texture, Rect2(Vector2.ZERO, Vector2(src.texture.get_size()) * zoom), false)
	var grid_size := src.get_atlas_grid_size()
	var lo := _coords_at(view.position)
	var hi := _coords_at(view.end)
	var step := Vector2(src.texture_region_size + src.separation) * zoom
	var origin := Vector2(src.margins) * zoom
	# Grid lines, in one draw call.
	var lines := PackedVector2Array()
	for x in range(lo.x, mini(hi.x + 2, grid_size.x + 1)):
		var px := origin.x + x * step.x
		lines.append_array([Vector2(px, view.position.y), Vector2(px, view.end.y)])
	for y in range(lo.y, mini(hi.y + 2, grid_size.y + 1)):
		var py := origin.y + y * step.y
		lines.append_array([Vector2(view.position.x, py), Vector2(view.end.x, py)])
	if not lines.is_empty():
		grid.draw_multiline(lines, Color(1, 1, 1, 0.12))
	# Markers of the visible tiles: terrain (bottom bar), solid (red), kind tag (blue).
	var kind_layer := -1
	for i in painter.tile_set.get_custom_data_layers_count():
		if painter.tile_set.get_custom_data_layer_name(i) == "idp_kind":
			kind_layer = i
	var physics := painter.tile_set.get_physics_layers_count() > 0
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not src.has_tile(c):
				continue
			var r := _tile_rect(src, c)
			var td := src.get_tile_data(c, 0)
			if td.terrain_set >= 0 and td.terrain >= 0:
				grid.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), painter.tile_set.get_terrain_color(td.terrain_set, td.terrain))
			if physics and td.get_collision_polygons_count(0) > 0:
				grid.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(4, 4)), Color(1, 0.35, 0.3))
			if kind_layer >= 0 and not str(td.get_custom_data_by_layer_id(kind_layer)).is_empty():
				grid.draw_rect(Rect2(r.position + Vector2(r.size.x - 5, 1), Vector2(4, 4)), Color(0.3, 0.85, 1))
	if selection.has_area():
		var a := _tile_rect(src, selection.position)
		var b := _tile_rect(src, selection.end - Vector2i.ONE)
		var sel := Rect2(a.position, b.end - a.position)
		grid.draw_rect(sel, Color(1, 0.85, 0.2, 0.18))
		grid.draw_rect(sel, Color(1, 0.85, 0.2), false, 2.0)

func _grid_input(event: InputEvent) -> void:
	if not _source():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = _coords_at(mb.position)
				selection = Rect2i(_drag_from, Vector2i.ONE)
				grid.queue_redraw()
			elif _drag_from.x >= 0:
				_drag_from = Vector2i(-1, -1)
				select_region(selection)
			grid.accept_event()
		elif mb.pressed and mb.ctrl_pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			set_zoom(zoom * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2))
			grid.accept_event()
	elif event is InputEventMouseMotion:
		var c := _coords_at(event.position)
		var src := _source()
		grid.tooltip_text = _tile_tooltip(src, c)
		if _drag_from.x >= 0:
			var lo := Vector2i(mini(c.x, _drag_from.x), mini(c.y, _drag_from.y))
			var hi := Vector2i(maxi(c.x, _drag_from.x), maxi(c.y, _drag_from.y))
			selection = Rect2i(lo, hi - lo + Vector2i.ONE)
			grid.queue_redraw()

func _tile_tooltip(src: TileSetAtlasSource, c: Vector2i) -> String:
	var t := src.get_tile_at_coords(c)
	if t == Vector2i(-1, -1):
		return "(%d, %d): empty" % [c.x, c.y]
	var parts: PackedStringArray = ["(%d, %d)" % [t.x, t.y]]
	var td := src.get_tile_data(t, 0)
	if td.terrain_set >= 0 and td.terrain >= 0:
		parts.append("terrain " + painter.tile_set.get_terrain_name(td.terrain_set, td.terrain))
	if painter.is_solid(source_id, t):
		parts.append("solid")
	var kind := painter.get_tile_kind(source_id, t)
	if not kind.is_empty():
		parts.append("kind " + kind)
	return ", ".join(parts)

func _update_info() -> void:
	if not _source():
		return
	if not selection.has_area():
		info.text = "Drag over tiles to pick them for the brushes. Red dot: solid, blue dot: tagged kind, bar: terrain."
	else:
		info.text = "Picked %dx%d tiles: the Terrain, Background and Decor brushes paint them (choose \"Palette tiles\" in the fill list)." % [selection.size.x, selection.size.y]

# --- Actions -----------------------------------------------------------------------------------

func _toggle_solid() -> void:
	if not has_selection():
		status_message.emit("Pick tiles in the palette first.")
		return
	var tiles := painter.tiles_in(source_id, selection)
	var all_solid := true
	for t in tiles:
		all_solid = all_solid and painter.is_solid(source_id, t)
	painter.set_collision(source_id, tiles, not all_solid)
	painter.save_tile_set()
	grid.queue_redraw()
	status_message.emit("%d tiles are %s." % [tiles.size(), "no longer solid" if all_solid else "now solid (collision)"])

func _make_terrain() -> void:
	if not has_selection():
		status_message.emit("Pick a 3x3 or 4x4 block of tiles in the palette first.")
		return
	var n := terrain_name.text.strip_edges()
	if n.is_empty():
		n = "%s terrain" % source_opt.get_item_text(source_opt.selected)
	var color := Color.from_hsv(randf(), 0.6, 0.85)
	var result := painter.make_terrain(source_id, selection, n, color, true)
	if result.x < 0:
		status_message.emit("Make terrain needs a 3x3 box (corners, edges, fill) or a 4x4 sides layout; the selection is %dx%d." % [selection.size.x, selection.size.y])
		return
	grid.queue_redraw()
	tileset_changed.emit()
	status_message.emit("Terrain \"%s\" created (terrain set %d). Pick it in the Terrain fill list; Generate cave can use it too." % [n, result.x])

func _tag() -> void:
	if not has_selection():
		status_message.emit("Pick tiles in the palette first.")
		return
	var kind := kind_edit.text.strip_edges().to_snake_case()
	var tiles := painter.tiles_in(source_id, selection)
	painter.tag_tiles(source_id, tiles, kind)
	painter.save_tile_set()
	grid.queue_redraw()
	tileset_changed.emit()
	status_message.emit("%d tiles tagged as %s." % [tiles.size(), kind] if not kind.is_empty() else "Tags removed from %d tiles." % tiles.size())

# --- Adding spritesheets ------------------------------------------------------------------------

func _pick_sheet() -> void:
	if not painter:
		return
	if not _file_dialog:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_file_dialog.title = "Add a spritesheet"
		_file_dialog.filters = PackedStringArray(["*.png, *.webp, *.jpg, *.jpeg, *.svg, *.tga, *.bmp ; Images"])
		_file_dialog.file_selected.connect(_ask_import)
		add_child(_file_dialog)
	_file_dialog.popup_file_dialog()

func _ask_import(path: String) -> void:
	_import_path = path
	if not _import_dialog:
		_import_dialog = ConfirmationDialog.new()
		_import_dialog.title = "Spritesheet"
		_import_dialog.ok_button_text = "Add"
		var box := VBoxContainer.new()
		MDSUi.scroll_content(_import_dialog, box)
		var g := GridContainer.new()
		g.columns = 3
		box.add_child(g)
		for f in ["Tile size", "Margin", "Separation"]:
			g.add_child(MDSUi.label(f))
			for axis in ["x", "y"]:
				var sp := SpinBox.new()
				sp.min_value = 0 if f != "Tile size" else 1
				sp.max_value = 1024
				sp.prefix = axis
				g.add_child(sp)
				_import_fields[f + axis] = sp
		var solid := CheckBox.new()
		solid.text = "Solid tiles (collision, for terrain sheets)"
		box.add_child(solid)
		_import_fields.solid = solid
		var note := MDSUi.hint("")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 320
		box.add_child(note)
		_import_fields.note = note
		_import_dialog.confirmed.connect(func() -> void:
			var tile := Vector2i(int(_import_fields["Tile sizex"].value), int(_import_fields["Tile sizey"].value))
			var margin := Vector2i(int(_import_fields.Marginx.value), int(_import_fields.Marginy.value))
			var sep := Vector2i(int(_import_fields.Separationx.value), int(_import_fields.Separationy.value))
			import_sheet(_import_path, tile, margin, sep, _import_fields.solid.button_pressed))
		add_child(_import_dialog)
	var grid_size := painter.tile_set.tile_size
	for axis in 2:
		_import_fields["Tile size" + "xy"[axis]].value = grid_size[axis]
	var tex := load(path) as Texture2D
	_import_fields.note.text = "%s is %dx%d px. Tiles of another size than the room grid (%dx%d) are scaled to fit it." % [path.get_file(), tex.get_width() if tex else 0, tex.get_height() if tex else 0, grid_size.x, grid_size.y]
	MDSUi.popup_fitted(_import_dialog, 380)

func import_sheet(path: String, tile: Vector2i, margin := Vector2i.ZERO, separation := Vector2i.ZERO, solid := false) -> int:
	var sid := painter.add_sheet(path, tile, margin, separation, solid)
	if sid < 0:
		status_message.emit("Could not add %s (not an image, or no tiles at that size)." % path)
		return sid
	refresh()
	show_source(sid)
	tileset_changed.emit()
	status_message.emit("Added %s (%d tiles). Drag over tiles to pick them." % [path.get_file(), _source().get_tiles_count()])
	return sid
