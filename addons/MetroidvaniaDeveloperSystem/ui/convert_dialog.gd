@tool
class_name IDPConvertDialog
extends ConfirmationDialog
## The Room view's "Convert to freeform..." dialog (see [IDPFreeformConverter]): styles,
## growth, corner radii, seed, what happens to the old terrain, and a Preview that applies
## the conversion so it can be looked at (Cancel takes it back out).

signal converted(report: Dictionary)

var view: IDPRoomView
var _styles: Array[IDPFreeformStyle] = []
var _rock: OptionButton
var _ledge: OptionButton
var _back: OptionButton
var _front: OptionButton
var _outside: OptionButton
var _growth: SpinBox
var _bowl: SpinBox
var _lip: SpinBox
var _seed: SpinBox
var _old: OptionButton
var _blockout: CheckBox
var _previewing := false

func _init() -> void:
	title = "Convert to freeform"
	ok_button_text = "Convert"
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(IDPUi.hint("Turns the room's solid tiles, static bodies and straight-edged freeform shapes into organic freeform rock, keeping every doorway, platform top and floor under objects where it is. Platforms become one-way ledges."))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_rock = _option(grid, "Rock style", "Style of the solid rock")
	_ledge = _option(grid, "Ledge style", "Style of the ledges made from platforms (one-way bodies and tiles)")
	_back = _option(grid, "Background tiles", "Turn the Background layer's tiles into freeform shapes of this style, or keep them")
	_front = _option(grid, "Foreground tiles", "Turn the Foreground layer's tiles into freeform shapes of this style, or keep them")
	_outside = _option(grid, "Fill outside shape", "Also cover the cells of the room's box outside its shape on the map with non-solid shapes of this style (deep ground over the rock's edges)")
	_growth = _spin(grid, "Growth", 0, 200, 100, "%", "How much faces grow: floors in low mounds, ceilings sagging in lobes, walls bulging (0: corners rounded only)")
	_bowl = _spin(grid, "Inside corners", 0, 200, 64, "px", "Radius of the bowls rounding inside corners")
	_lip = _spin(grid, "Outside corners", 0, 100, 18, "px", "Radius of the lips rounding outside corners")
	_seed = _spin(grid, "Seed", 0, 99999, 0, "", "Same seed, same rock")
	grid.add_child(IDPUi.label("Old terrain"))
	_old = OptionButton.new()
	_old.add_item("Keep it, hidden")
	_old.add_item("Remove it")
	_old.tooltip_text = "Hidden: the old tiles move to a disabled <Layer>Blockout layer and old bodies are hidden without collision, all still in the scene. Remove: they go (Ctrl+Z still brings them back)"
	grid.add_child(_old)
	_blockout = CheckBox.new()
	_blockout.text = "Convert straight-edged freeform shapes"
	_blockout.button_pressed = true
	_blockout.tooltip_text = "Solid freeform shapes with Smooth off (a blockout drawn with rectangles) become rock too"
	box.add_child(_blockout)
	add_button("Preview", false, "preview")
	custom_action.connect(func(action: StringName) -> void:
		if action == &"preview":
			preview())
	confirmed.connect(_on_confirmed)
	canceled.connect(_take_back)
	close_requested.connect(_take_back)

func _option(grid: GridContainer, text: String, tip: String) -> OptionButton:
	grid.add_child(IDPUi.label(text))
	var o := OptionButton.new()
	o.tooltip_text = tip
	o.fit_to_longest_item = false
	o.custom_minimum_size.x = 240
	grid.add_child(o)
	return o

func _spin(grid: GridContainer, text: String, lo: float, hi: float, value: float, suffix: String, tip: String) -> SpinBox:
	grid.add_child(IDPUi.label(text))
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.suffix = suffix
	s.tooltip_text = tip
	grid.add_child(s)
	return s

## Opens the dialog for the view's room.
func open(p_view: IDPRoomView, styles: Array[IDPFreeformStyle], current: IDPFreeformStyle) -> void:
	view = p_view
	_styles = styles
	_previewing = false
	_fill(_rock, "", current, func(st: IDPFreeformStyle) -> bool: return st.get_role() == IDPFreeformStyle.Role.TERRAIN and st.solid)
	_fill(_ledge, "Rock style, as one-way ledges", null, func(st: IDPFreeformStyle) -> bool: return st.get_role() == IDPFreeformStyle.Role.PLATFORM)
	_fill(_back, "Keep as tiles", null, func(_st: IDPFreeformStyle) -> bool: return false)
	_fill(_front, "Keep as tiles", null, func(_st: IDPFreeformStyle) -> bool: return false)
	_fill(_outside, "No", null, func(_st: IDPFreeformStyle) -> bool: return false)
	_seed.value = absi(hash(view.room_id)) % 10000
	popup_centered()

## Lists the styles; picks [param current], else the first one [param prefer] accepts, else
## the empty choice (when [param empty] is given) or the first style.
func _fill(o: OptionButton, empty: String, current: IDPFreeformStyle, prefer: Callable) -> void:
	o.clear()
	if not empty.is_empty():
		o.add_item(empty)
		o.set_item_metadata(0, null)
	var pick := -1
	for st in _styles:
		o.add_item(st.get_list_name())
		o.set_item_metadata(o.item_count - 1, st)
		if pick < 0 and (st == current or (current == null and prefer.call(st))):
			pick = o.item_count - 1
	o.select(pick if pick >= 0 else 0)

func _style(o: OptionButton) -> IDPFreeformStyle:
	return o.get_item_metadata(o.selected) if o.selected >= 0 else null

func _run() -> Dictionary:
	var painter := view.painter
	painter.checkpoint()
	var conv := IDPFreeformConverter.new()
	conv.rock_style = _style(_rock)
	conv.ledge_style = _style(_ledge)
	conv.back_style = _style(_back)
	conv.front_style = _style(_front)
	conv.growth = _growth.value / 100.0
	conv.bowl_radius = _bowl.value
	conv.lip_radius = _lip.value
	conv.seed_value = int(_seed.value)
	conv.keep_old = _old.selected == 0
	conv.include_blockout = _blockout.button_pressed
	conv.use_world_room(view.world, view.room_id)
	var r := conv.convert(painter)
	if not r.error.is_empty():
		painter.undo()
		return r
	var deep := _style(_outside)
	if deep:
		r.outside = IDPNotchFill.fill(painter, view.world.get_local_rects(view.room_id), deep)
	return r

func preview() -> void:
	if _previewing:
		view.painter.undo()
	var r := _run()
	_previewing = r.error.is_empty()
	view.report_conversion(r, true)

func _on_confirmed() -> void:
	if not _previewing:
		var r := _run()
		view.report_conversion(r, false)
		converted.emit(r)
	else:
		view.report_conversion({}, false)
	_previewing = false

func _take_back() -> void:
	if _previewing and view and view.painter:
		view.painter.undo()
		view.report_conversion({"error": "Conversion cancelled."}, false)
	_previewing = false
