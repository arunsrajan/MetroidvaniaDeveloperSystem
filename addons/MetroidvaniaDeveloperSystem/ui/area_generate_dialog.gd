@tool
class_name MDSAreaGenerateDialog
extends ConfirmationDialog
## The settings of an area generated in a box of the world map (the Generate tool, the Areas
## tab), with a preview: name, color, shape (rectangle or square, irregular blocks, freeform,
## hybrid), curved and slanted corners, room sizes, irregular rooms, shafts, loops, how ragged,
## corridors and the seed.
## Generate makes the area's rooms and doors ([MDSAreaGenerator]), and connects it to the
## areas it touches.

## After Generate: {area, rooms, doors, links}.
signal generated(result: Dictionary)

var world: MDSWorld
var box := Rect2i()
var layer := 0
var generator: MDSAreaGenerator

var _name: LineEdit
var _color: ColorPickerButton
var _shape: OptionButton
var _min_w: SpinBox
var _min_h: SpinBox
var _max_w: SpinBox
var _max_h: SpinBox
var _curves: SpinBox
var _slants: SpinBox
var _irregular: SpinBox
var _shafts: SpinBox
var _loops: SpinBox
var _rough: SpinBox
var _tendrils: SpinBox
var _seed: SpinBox
var _link: CheckBox
var _info: Label
var _preview_box: Control
var _preview: Dictionary = {}
var _preview_rooms: Dictionary = {} ## room index -> its outline polygons (cells)
var _preview_rim: Array[PackedVector2Array] = []
var _taken: Dictionary = {} ## box-local cells other rooms cover
var _syncing := false

func _init() -> void:
	title = "Generate area"
	ok_button_text = "Generate"
	var content := VBoxContainer.new()
	content.add_child(MDSUi.hint("An area made of rooms with doors between them, in the box you dragged. Cells other rooms cover are left out. It connects to the areas it touches."))
	var grid := GridContainer.new()
	grid.columns = 2
	content.add_child(grid)
	grid.add_child(MDSUi.label("Name"))
	var name_row := HBoxContainer.new()
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.tooltip_text = "The area's name (an existing area's name adds the rooms to it)"
	name_row.add_child(_name)
	var dice := MDSUi.button("Random", "Another name")
	dice.pressed.connect(func() -> void:
		var keep := generator.seed_value
		generator.seed_value = randi()
		_name.text = generator.random_name(world)
		generator.seed_value = keep)
	name_row.add_child(dice)
	grid.add_child(name_row)
	grid.add_child(MDSUi.label("Color"))
	_color = ColorPickerButton.new()
	_color.edit_alpha = false
	_color.custom_minimum_size = Vector2(60, 24)
	_color.color_changed.connect(func(_c: Color) -> void: _preview_box.queue_redraw())
	grid.add_child(_color)
	grid.add_child(MDSUi.label("Shape"))
	_shape = OptionButton.new()
	for i in MDSAreaGenerator.SHAPE_NAMES.size():
		_shape.add_item(MDSAreaGenerator.SHAPE_NAMES[i], i)
	_shape.tooltip_text = "Rectangle or square: the whole box. Irregular: blocks joined together. Freeform: a curvy blob with corridors. Hybrid: a blob with halls, towers and corridors. Curves and Slants shape the corners of all of them"
	_shape.item_selected.connect(func(_i: int) -> void: _changed())
	grid.add_child(_shape)
	_curves = _percent(grid, "Curves", "Share of the outline's corners rounded into curves, and of the corridors that curve. 0 with Slants 0: straight sides and sharp corners")
	_slants = _percent(grid, "Slants", "Share of the outline's corners cut on a slant, of the blocks with a slanted side, and of the corridors that turn at angles")
	_min_w = _spin(1, 16)
	_min_h = _spin(1, 16)
	_size_row(grid, "Smallest room", _min_w, _min_h, "Paint cells (World settings > Paint cell; a quarter of the default room size unless set)")
	_max_w = _spin(1, 24)
	_max_h = _spin(1, 24)
	_size_row(grid, "Largest room", _max_w, _max_h, "Paint cells")
	_irregular = _percent(grid, "Irregular rooms", "Share of rooms joined with a neighbour into one L, T or U shaped room")
	_shafts = _percent(grid, "Shafts", "Share of tall, narrow rooms to climb or fall through")
	_loops = _percent(grid, "Loops", "Share of the other neighbouring rooms that get a door too: more ways around. 0: one way to each room")
	_rough = _percent(grid, "Ragged outline", "How ragged a freeform or hybrid outline is")
	grid.add_child(MDSUi.label("Corridors"))
	_tendrils = _spin(0, 8)
	_tendrils.tooltip_text = "Corridors reaching out of a freeform or hybrid area"
	grid.add_child(_tendrils)
	grid.add_child(MDSUi.label("Seed"))
	var seed_row := HBoxContainer.new()
	_seed = _spin(0, 999999)
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed)
	var reroll := MDSUi.button("New", "Another layout")
	reroll.pressed.connect(func() -> void: _seed.value = randi() % 1000000)
	seed_row.add_child(reroll)
	grid.add_child(seed_row)
	_link = CheckBox.new()
	_link.text = "Connect to the areas it touches"
	_link.button_pressed = true
	_link.tooltip_text = "A door to each area it touches, where they meet (taken out again if you drag them apart with the Area tool)"
	content.add_child(_link)
	_preview_box = Control.new()
	_preview_box.custom_minimum_size = Vector2(0, 210) * MDSUi.editor_scale()
	_preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_box.draw.connect(_draw_preview)
	_preview_box.resized.connect(func() -> void: _preview_box.queue_redraw())
	content.add_child(_preview_box)
	_info = MDSUi.hint("")
	content.add_child(_info)
	MDSUi.scroll_content(self, content)
	confirmed.connect(generate_now)

func _spin(lo: float, hi: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value_changed.connect(func(_v: float) -> void: _changed())
	return s

func _percent(grid: GridContainer, text: String, tooltip: String) -> SpinBox:
	grid.add_child(MDSUi.label(text))
	var s := _spin(0, 100)
	s.suffix = "%"
	s.tooltip_text = tooltip
	grid.add_child(s)
	return s

func _size_row(grid: GridContainer, text: String, w: SpinBox, h: SpinBox, tooltip: String) -> void:
	grid.add_child(MDSUi.label(text))
	var row := HBoxContainer.new()
	w.tooltip_text = tooltip
	h.tooltip_text = tooltip
	row.add_child(w)
	row.add_child(MDSUi.label("x"))
	row.add_child(h)
	grid.add_child(row)

## Opens the dialog for an area in [param p_box] (paint cells) on [param p_layer], with the
## settings of [param p_generator] (changed as you edit them).
func open(p_world: MDSWorld, p_box: Rect2i, p_layer: int, p_generator: MDSAreaGenerator) -> void:
	world = p_world
	box = p_box
	layer = p_layer
	generator = p_generator
	_taken.clear()
	var occupied := MDSAreaTools.occupied(world, layer)
	for c: Vector2i in occupied:
		if box.has_point(c):
			_taken[c - box.position] = true
	_syncing = true
	_name.text = generator.random_name(world)
	_color.color = MDSAreaGenerator.free_color(world, world.get_areas().size())
	_shape.select(generator.shape)
	_min_w.value = generator.room_min.x
	_min_h.value = generator.room_min.y
	_max_w.value = generator.room_max.x
	_max_h.value = generator.room_max.y
	_curves.value = roundf(generator.curves * 100.0)
	_slants.value = roundf(generator.slants * 100.0)
	_irregular.value = roundf(generator.irregularity * 100.0)
	_shafts.value = roundf(generator.shafts * 100.0)
	_loops.value = roundf(generator.loops * 100.0)
	_rough.value = roundf(generator.roughness * 100.0)
	_tendrils.value = generator.tendrils
	_seed.value = generator.seed_value
	_syncing = false
	_refresh()
	MDSUi.popup_fitted(self, 560)

func get_area_name() -> String:
	return _name.text.strip_edges()

func set_area_name(text: String) -> void:
	_name.text = text

func set_shape(shape: MDSAreaGenerator.Shape) -> void:
	_shape.select(shape)
	_changed()

## What Generate will make: {cells, rooms, doors}, box-local.
func get_preview() -> Dictionary:
	return _preview

func _changed() -> void:
	if _syncing or not generator:
		return
	_read()
	_refresh()

func _read() -> void:
	generator.shape = _shape.get_selected_id() as MDSAreaGenerator.Shape
	generator.room_min = Vector2i(int(_min_w.value), int(_min_h.value))
	generator.room_max = Vector2i(maxi(int(_max_w.value), int(_min_w.value)), maxi(int(_max_h.value), int(_min_h.value)))
	generator.curves = _curves.value / 100.0
	generator.slants = _slants.value / 100.0
	generator.irregularity = _irregular.value / 100.0
	generator.shafts = _shafts.value / 100.0
	generator.loops = _loops.value / 100.0
	generator.roughness = _rough.value / 100.0
	generator.tendrils = int(_tendrils.value)
	generator.seed_value = int(_seed.value)

func _refresh() -> void:
	_preview = generator.preview(box.size, _taken)
	_preview_rooms.clear()
	var pieces: Array[PackedVector2Array] = []
	for i in _preview.shapes.size():
		_preview_rooms[i] = MDSMapStyle.drawable(_preview.shapes[i])
		pieces.append_array(_preview_rooms[i])
	_preview_rim = MDSMapStyle.drawable(MDSGeometry.union_all(pieces, INF))
	var s := world.get_paint_cell()
	_info.text = "%d x %d cells (%d x %d px): %d rooms, %d doors." % [box.size.x, box.size.y, box.size.x * s.x, box.size.y * s.y, _preview.rooms.size(), _preview.doors.size()]
	if _preview.rooms.is_empty():
		_info.text = "The box is full of rooms already: drag it over free space."
	get_ok_button().disabled = _preview.rooms.is_empty()
	_preview_box.queue_redraw()

func _draw_preview() -> void:
	var area := Rect2(Vector2.ZERO, _preview_box.size)
	_preview_box.draw_rect(area, Color(0.07, 0.07, 0.09))
	if box.size.x <= 0 or box.size.y <= 0:
		return
	var k := minf((area.size.x - 16.0) / box.size.x, (area.size.y - 16.0) / box.size.y)
	var offset := (area.size - Vector2(box.size) * k) / 2.0
	var to_screen := func(p: Vector2) -> Vector2: return offset + p * k
	for c: Vector2i in _taken:
		_preview_box.draw_rect(Rect2(to_screen.call(Vector2(c)), Vector2(k, k)), Color(0.3, 0.3, 0.33))
	var fills: Dictionary = {}
	var base := _color.color
	for i in _preview_rooms:
		fills[i] = base.lightened(0.12 * (i % 3)) if i % 2 == 0 else base.darkened(0.08 * (i % 3))
	MDSMapStyle.draw_glow_polygons(_preview_box, _preview_rooms, to_screen, k / 20.0, fills, base, _preview_rim)
	for d: Array in _preview.get("doors", []):
		var p: Vector2 = to_screen.call(Vector2(d[0]) + Vector2(0.5, 0.5) + Vector2(d[1]) * 0.5)
		_preview_box.draw_circle(p, clampf(k * 0.16, 2.0, 5.0), Color(1, 0.95, 0.7))

## Makes the area now (what Generate does).
func generate_now() -> void:
	if not world or not generator:
		return
	_read()
	if generator.preview(box.size, _taken).rooms.is_empty():
		return
	var name := get_area_name()
	if name.is_empty():
		name = generator.random_name(world)
	world.checkpoint()
	var result := generator.generate(world, box, layer, name, _color.color)
	result.links = MDSAreaTools.link_touching(world, MDSAreaTools.group_rooms(world, name, layer), layer) if _link.button_pressed else []
	hide()
	generated.emit(result)
