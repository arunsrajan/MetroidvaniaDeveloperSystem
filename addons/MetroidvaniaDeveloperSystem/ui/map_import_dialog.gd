@tool
class_name MDSMapImportDialog
extends ConfirmationDialog
## Import map image: a picture of a map (PNG and other images: exported from MDS or MetSys,
## made in another tool, drawn, a screenshot) becomes rooms, areas and doors on the world map
## (see [MDSMapImageImporter]). The preview shows the grid found and the rooms, colored by area,
## with their doors; the grid, the colors and how rooms are told apart can be set. Import makes
## them with one undo step.

## After Import: [method MDSMapImageImporter.apply]'s result.
signal imported(result: Dictionary)

const IMAGE_FILTERS: PackedStringArray = ["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.svg ; Images"]
enum Place { RIGHT, DROP, KEEP }

var world: MDSWorld
var layer := 0
var importer := MDSMapImageImporter.new()
## Where a picture dropped on the map was let go (world px), else INF.
var drop_pos := Vector2.INF

var _path: LineEdit
var _auto: CheckBox
var _cell_w: SpinBox
var _cell_h: SpinBox
var _off_x: SpinBox
var _off_y: SpinBox
var _tolerance: SpinBox
var _ink: SpinBox
var _fill: SpinBox
var _mode: OptionButton
var _doors: CheckBox
var _connect: CheckBox
var _across: SpinBox
var _scale_x: SpinBox
var _scale_y: SpinBox
var _place: OptionButton
var _areas_box: VBoxContainer
var _area_names: Array[LineEdit] = []
var _info: Label
var _preview: Control
var _texture: ImageTexture
var _timer: Timer
var _file_dialog: EditorFileDialog
var _syncing := false

func _init() -> void:
	title = "Import map image"
	ok_button_text = "Import"
	var content := VBoxContainer.new()
	content.add_child(MDSUi.hint("A picture of a map becomes rooms on the map: its grid's cells are paint cells, its colors areas, cells parted by a wall line separate rooms, a gap in a wall or a gate marker on it a door. A map drawn with no grid (Hollow Knight, Silksong) is read as a shape per area, each split into rooms with doors. Cells other rooms have are left out. One undo takes it back."))
	var file_row := HBoxContainer.new()
	_path = LineEdit.new()
	_path.editable = false
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.placeholder_text = "No picture yet"
	file_row.add_child(_path)
	var pick := MDSUi.button("Pick...", "Pick a picture of a map (PNG, JPG, WebP, BMP, TGA, SVG), in the project or anywhere on disk")
	pick.pressed.connect(_pick_file)
	file_row.add_child(pick)
	content.add_child(file_row)
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(0, 240) * MDSUi.editor_scale()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.draw.connect(_draw_preview)
	_preview.resized.connect(func() -> void: _preview.queue_redraw())
	content.add_child(_preview)
	_info = MDSUi.hint("")
	content.add_child(_info)
	var grid := GridContainer.new()
	grid.columns = 2
	content.add_child(grid)
	grid.add_child(MDSUi.label("Grid"))
	_auto = CheckBox.new()
	_auto.text = "Find it"
	_auto.button_pressed = true
	_auto.tooltip_text = "Find the map's grid from where its rooms' edges are (across and down on their own). Off: the cell size and offset below. A picture MDS exported has a sidecar file that gives it exactly"
	_auto.toggled.connect(func(_on: bool) -> void: _changed())
	grid.add_child(_auto)
	_cell_w = _spin(1, 4000, 0.01)
	_cell_h = _spin(1, 4000, 0.01)
	_pair(grid, "Cell size (px)", _cell_w, _cell_h, "One cell of the map's grid in the picture, across and down")
	_off_x = _spin(-4000, 4000, 0.01)
	_off_y = _spin(-4000, 4000, 0.01)
	_pair(grid, "Cell starts at (px)", _off_x, _off_y, "Where a cell's top-left corner is in the picture")
	_tolerance = _spin(0.01, 1.0, 0.01)
	_tolerance.value = importer.color_tolerance
	_row(grid, "Same area within", _tolerance, "How far apart two room colors may be and be one area (hue and saturation count, brightness less)")
	_ink = _spin(0.0, 1.0, 0.01)
	_ink.value = importer.ink_level
	_row(grid, "Ink darker than", _ink, "Pixels darker than this are walls and outlines, not rooms")
	_fill = _spin(0.05, 1.0, 0.05)
	_fill.value = importer.min_fill
	_row(grid, "Room cell filled", _fill, "The share of a cell's middle that must be room color for it to be a room's")
	grid.add_child(MDSUi.label("Rooms"))
	_mode = OptionButton.new()
	_mode.add_item("Parted by walls", MDSMapImageImporter.RoomMode.WALLS)
	_mode.add_item("One per color region", MDSMapImageImporter.RoomMode.COLOR_REGIONS)
	_mode.add_item("One per cell", MDSMapImageImporter.RoomMode.CELLS)
	_mode.add_item("Drawn map: a shape per area", MDSMapImageImporter.RoomMode.SHAPES)
	_mode.tooltip_text = "Parted by walls: cells of one area with no wall line between them are one room. One per color region: the cells of one area that touch. One per cell: every cell its own room. Drawn map: a map with no grid (Hollow Knight, Silksong), each area a shape filled with its color: each shape is split into rooms with doors, keeping its outline (used too when no grid is found)"
	_mode.item_selected.connect(func(_i: int) -> void: _changed())
	grid.add_child(_mode)
	_scale_x = _spin(1, 16, 1)
	_scale_y = _spin(1, 16, 1)
	_scale_x.value = 1
	_scale_y.value = 1
	_across = _spin(10, 1000, 1)
	_across.value = importer.shape_cells_across
	_row(grid, "Drawn map: cells across", _across, "A map drawn with no grid: how many paint cells its width takes on the world (more: bigger rooms on the map, more of them, thin corridors kept)")
	_across.value_changed.connect(func(_v: float) -> void: _changed())
	_pair(grid, "Paint cells per cell", _scale_x, _scale_y, "How many paint cells of the world one cell of the picture's grid covers, across and down (a MetSys map's cell is a whole screen: 4 x 4 by default)")
	grid.add_child(MDSUi.label("Place"))
	_place = OptionButton.new()
	_place.add_item("Right of the map", Place.RIGHT)
	_place.add_item("Where it was dropped", Place.DROP)
	_place.add_item("Where they were (sidecar)", Place.KEEP)
	_place.tooltip_text = "Right of the rooms on this layer; where the picture was dropped on the map; or, for a picture MDS exported with its sidecar, on the same paint cells as the rooms it shows"
	grid.add_child(_place)
	_doors = CheckBox.new()
	_doors.text = "Doors: gaps in walls, gate markers"
	_doors.button_pressed = true
	_doors.tooltip_text = "A gap in a wall between two rooms, or a gate marker (a bright square, as MDS draws gates) on it, is a door: a pair of connected gates"
	_doors.toggled.connect(func(_on: bool) -> void: _changed())
	content.add_child(_doors)
	_connect = CheckBox.new()
	_connect.text = "Doors to rooms no door reaches"
	_connect.button_pressed = true
	_connect.tooltip_text = "Rooms no door reaches get one to a room they touch, so every room can be walked to"
	content.add_child(_connect)
	content.add_child(MDSUi.label("Areas (biggest first)"))
	_areas_box = VBoxContainer.new()
	content.add_child(_areas_box)
	MDSUi.scroll_content(self, content)
	for s: SpinBox in [_cell_w, _cell_h, _off_x, _off_y, _tolerance, _ink, _fill]:
		s.value_changed.connect(func(_v: float) -> void: _changed(s))
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.35
	_timer.timeout.connect(refresh)
	add_child(_timer)
	confirmed.connect(import_now)

func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

func _row(grid: GridContainer, text: String, s: SpinBox, tip: String) -> void:
	grid.add_child(MDSUi.label(text))
	s.tooltip_text = tip
	grid.add_child(s)

func _pair(grid: GridContainer, text: String, a: SpinBox, b: SpinBox, tip: String) -> void:
	grid.add_child(MDSUi.label(text))
	var row := HBoxContainer.new()
	a.tooltip_text = tip
	b.tooltip_text = tip
	row.add_child(a)
	row.add_child(b)
	grid.add_child(row)

## Opens the dialog for [param p_world]'s [param p_layer], with the picture [param path] if
## given ([param at]: where it was dropped on the map, world px).
func open(p_world: MDSWorld, p_layer: int, path := "", at := Vector2.INF) -> void:
	world = p_world
	layer = p_layer
	drop_pos = at
	var cell := world.get_paint_cell()
	importer.cell_aspect = cell.x / cell.y if cell.y > 0.0 else 0.0
	_place.set_item_disabled(Place.DROP, at == Vector2.INF)
	_place.select(Place.DROP if at != Vector2.INF else Place.RIGHT)
	if not path.is_empty():
		load_picture(path)
	MDSUi.popup_fitted(self, 620)

## Loads the picture [param path] and reads it.
func load_picture(path: String) -> Error:
	var err := importer.load_image(path)
	if err != OK:
		_info.text = "Could not load %s (error %d)." % [path, err]
		return err
	_path.text = path
	_texture = ImageTexture.create_from_image(importer.image)
	_syncing = true
	_auto.button_pressed = importer.sidecar.is_empty()
	_place.set_item_disabled(Place.KEEP, importer.sidecar.is_empty())
	if not importer.sidecar.is_empty():
		_place.select(Place.KEEP)
		_cell_w.value = importer.cell_size.x
		_cell_h.value = importer.cell_size.y
		_off_x.value = importer.grid_offset.x
		_off_y.value = importer.grid_offset.y
	_syncing = false
	refresh()
	return OK

func _changed(from: SpinBox = null) -> void:
	if _syncing:
		return
	# Setting the grid by hand: it isn't found any more.
	if from in [_cell_w, _cell_h, _off_x, _off_y]:
		_syncing = true
		_auto.button_pressed = false
		_syncing = false
	_timer.start()

## Reads the picture again with the settings.
func refresh() -> void:
	if not importer.image:
		return
	_read()
	var found := importer.analyze()
	_syncing = true
	_cell_w.value = found.cell_size.x
	_cell_h.value = found.cell_size.y
	_off_x.value = found.grid_offset.x
	_off_y.value = found.grid_offset.y
	_syncing = false
	var keep: PackedStringArray = []
	for e in _area_names:
		keep.append(e.text)
	for c in _areas_box.get_children():
		c.queue_free()
	_area_names.clear()
	for i in found.areas.size():
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = found.areas[i].color
		swatch.custom_minimum_size = Vector2(22, 18) * MDSUi.editor_scale()
		row.add_child(swatch)
		var name := LineEdit.new()
		name.placeholder_text = "Imported area (%d cells)" % found.areas[i].cells.size()
		name.text = keep[i] if i < keep.size() else ""
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.tooltip_text = "The area's name (an existing area's name puts the rooms in it)"
		row.add_child(name)
		_areas_box.add_child(row)
		_area_names.append(name)
	var text := "%d rooms, %d areas, %d doors; grid %.1f x %.1f px%s." % [found.rooms.size(), found.areas.size(), found.doors.size(), found.cell_size.x, found.cell_size.y, " (found)" if found.grid_found else (" (sidecar)" if not importer.sidecar.is_empty() else "")]
	if found.get("shapes", false):
		text = "A drawn map: %d areas, %d rooms, %d doors, one paint cell every %.1f x %.1f px of it." % [found.areas.size(), found.rooms.size(), found.doors.size(), found.cell_size.x, found.cell_size.y]
	if not found.warnings.is_empty():
		text += " " + " ".join(found.warnings)
	_info.text = text
	get_ok_button().disabled = found.rooms.is_empty()
	_preview.queue_redraw()

func _read() -> void:
	importer.auto_grid = _auto.button_pressed
	if not importer.auto_grid:
		importer.cell_size = Vector2(_cell_w.value, _cell_h.value)
		importer.grid_offset = Vector2(_off_x.value, _off_y.value)
	importer.color_tolerance = _tolerance.value
	importer.ink_level = _ink.value
	importer.min_fill = _fill.value
	importer.room_mode = _mode.get_selected_id()
	importer.detect_doors = _doors.button_pressed
	importer.connect_unreached = _connect.button_pressed
	importer.cells_per_map_cell = Vector2i(int(_scale_x.value), int(_scale_y.value))
	importer.shape_cells_across = int(_across.value)

## The names typed for the areas, in their order ("" for none).
func area_names() -> Array:
	return _area_names.map(func(e: LineEdit) -> String: return e.text.strip_edges())

## Makes the rooms (one undo step). Returns [method MDSMapImageImporter.apply]'s result.
func import_now() -> Dictionary:
	if not world or not importer.image:
		return {}
	_read()
	if importer.found.is_empty():
		importer.analyze()
	if importer.found.rooms.is_empty():
		return {}
	world.checkpoint()
	var at := Vector2i.MAX
	var keep := false
	match _place.get_selected_id():
		Place.DROP:
			if drop_pos != Vector2.INF:
				at = world.world_to_cell(drop_pos)
		Place.KEEP:
			keep = not importer.sidecar.is_empty()
	var r := importer.apply(world, layer, at, area_names(), keep)
	hide()
	imported.emit(r)
	return r

func _pick_file() -> void:
	if not _file_dialog:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = IMAGE_FILTERS
		_file_dialog.file_selected.connect(func(p: String) -> void: load_picture(p))
		add_child(_file_dialog)
	_file_dialog.popup_file_dialog()

## The picture, its grid, and the rooms found on it colored by area, with their doors.
func _draw_preview() -> void:
	var box := Rect2(Vector2.ZERO, _preview.size)
	_preview.draw_rect(box, Color(0, 0, 0, 0.35))
	if not _texture:
		return
	var img_size := Vector2(_texture.get_size())
	var k := minf(box.size.x / img_size.x, box.size.y / img_size.y)
	var at := (box.size - img_size * k) / 2.0
	_preview.draw_texture_rect(_texture, Rect2(at, img_size * k), false, Color(1, 1, 1, 0.55))
	var found := importer.found
	if found.is_empty():
		return
	var cell: Vector2 = found.cell_size * k
	var off: Vector2 = at + found.grid_offset * k
	# Grid lines where they are a few px apart.
	if cell.x >= 4.0 and cell.y >= 4.0:
		var x := off.x - floorf((off.x - at.x) / cell.x) * cell.x
		while x <= at.x + img_size.x * k:
			_preview.draw_line(Vector2(x, at.y), Vector2(x, at.y + img_size.y * k), Color(1, 1, 1, 0.12))
			x += cell.x
		var y := off.y - floorf((off.y - at.y) / cell.y) * cell.y
		while y <= at.y + img_size.y * k:
			_preview.draw_line(Vector2(at.x, y), Vector2(at.x + img_size.x * k, y), Color(1, 1, 1, 0.12))
			y += cell.y
	var cells: Dictionary = found.cells
	var room_of: Dictionary = {}
	for i in found.rooms.size():
		for c: Vector2i in found.rooms[i].cells:
			room_of[c] = i
	# Lines and doors no bigger than the cells are (a drawn map's are a few px here).
	var small := minf(cell.x, cell.y)
	var wall := clampf(small * 0.2, 0.5, 1.5)
	var dot := clampf(small * 0.35, 1.0, 3.5)
	for c: Vector2i in cells:
		var col: Color = found.areas[cells[c]].color
		# Dark fills (a drawn map's) shown lighter, to be seen over the picture.
		if col.get_luminance() < 0.35:
			col = col.lightened(0.45)
		var r := Rect2(off + Vector2(c) * cell, cell)
		_preview.draw_rect(r, Color(col, 0.55))
		# Walls: where the next cell is another room's, or none.
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if room_of.get(c + d, -1) != room_of[c]:
				var a := r.position + (Vector2(r.size.x, 0) if d == Vector2i.RIGHT else Vector2.ZERO) + (Vector2(0, r.size.y) if d == Vector2i.DOWN else Vector2.ZERO)
				var b := a + (Vector2(0, r.size.y) if d.x != 0 else Vector2(r.size.x, 0))
				_preview.draw_line(a, b, Color.WHITE, wall)
	for d: Dictionary in found.doors:
		var c: Vector2i = d.cell
		var r := Rect2(off + Vector2(c) * cell, cell)
		var p: Vector2 = r.position + (Vector2(r.size.x, r.size.y * d.t) if d.side == "right" else Vector2(r.size.x * d.t, r.size.y))
		_preview.draw_circle(p, dot, Color(1, 0.85, 0.2))
