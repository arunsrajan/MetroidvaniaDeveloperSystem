@tool
class_name IDPDecorateDialog
extends ConfirmationDialog
## The Room view's "Decorate freeform..." dialog (see [IDPFreeformDecorator]): what to place
## (hanging stamps, floor plants, background structures, foreground leaves), from which
## stamp set and styles, how much, and a seed. Preview places it so it can be looked at;
## Cancel takes it back out. Running it again replaces the earlier decoration.

var view: IDPRoomView
var _styles: Array[IDPFreeformStyle] = []
var _sets: Array[IDPStampSet] = []
var _set: OptionButton
var _hang: CheckBox
var _hang_cat: OptionButton
var _plants: CheckBox
var _plant_box: HFlowContainer
var _structs: CheckBox
var _kind_box: HFlowContainer
var _struct_style: OptionButton
var _leaf_cat: OptionButton
var _front: CheckBox
var _front_style: OptionButton
var _density: SpinBox
var _seed: SpinBox
var _previewing := false

func _init() -> void:
	title = "Decorate freeform"
	ok_button_text = "Decorate"
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 440
	add_child(box)
	box.add_child(IDPUi.hint("Places scenery relative to the room's freeform rock, never over doorways, platforms or anything in the room. Running it again replaces what it placed before."))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(IDPUi.label("Stamp set"))
	_set = OptionButton.new()
	_set.item_selected.connect(func(_i: int) -> void: _fill_categories())
	grid.add_child(_set)
	_hang = _toggle(grid, "Hanging", "Stamps hung under ceilings and ledges")
	_hang_cat = OptionButton.new()
	grid.add_child(_hang_cat)
	_plants = _toggle(grid, "Floor plants", "Stamps along floors: tick the categories below")
	grid.add_child(Control.new())
	_plant_box = HFlowContainer.new()
	box.add_child(_plant_box)
	var grid2 := GridContainer.new()
	grid2.columns = 2
	box.add_child(grid2)
	_structs = _toggle(grid2, "Structures", "Background shapes standing on flat floors (or hanging under flat ceilings): tick the kinds below")
	grid2.add_child(Control.new())
	_kind_box = HFlowContainer.new()
	box.add_child(_kind_box)
	for i in IDPShapeGenerators.NAMES.size():
		var cb := CheckBox.new()
		cb.text = IDPShapeGenerators.NAMES[i]
		cb.tooltip_text = IDPShapeGenerators.TIPS[i]
		cb.button_pressed = i in [IDPShapeGenerators.Kind.COLUMN, IDPShapeGenerators.Kind.ARCH, IDPShapeGenerators.Kind.GARDEN_WALL]
		cb.set_meta(&"kind", i)
		_kind_box.add_child(cb)
	var grid3 := GridContainer.new()
	grid3.columns = 2
	box.add_child(grid3)
	grid3.add_child(IDPUi.label("Structure style"))
	_struct_style = OptionButton.new()
	grid3.add_child(_struct_style)
	grid3.add_child(IDPUi.label("Leaves on them"))
	_leaf_cat = OptionButton.new()
	grid3.add_child(_leaf_cat)
	_front = _toggle(grid3, "Foreground", "Leaf silhouettes framing the room's free corners, in front of everything")
	_front_style = OptionButton.new()
	grid3.add_child(_front_style)
	grid3.add_child(IDPUi.label("Density"))
	_density = SpinBox.new()
	_density.min_value = 10
	_density.max_value = 300
	_density.value = 100
	_density.suffix = "%"
	grid3.add_child(_density)
	grid3.add_child(IDPUi.label("Seed"))
	_seed = SpinBox.new()
	_seed.max_value = 99999
	_seed.tooltip_text = "Same seed, same decoration"
	grid3.add_child(_seed)
	for o in [_set, _hang_cat, _struct_style, _leaf_cat, _front_style]:
		o.fit_to_longest_item = false
		o.custom_minimum_size.x = 220
	add_button("Preview", false, "preview")
	custom_action.connect(func(action: StringName) -> void:
		if action == &"preview":
			preview())
	confirmed.connect(_on_confirmed)
	canceled.connect(_take_back)
	close_requested.connect(_take_back)

func _toggle(grid: GridContainer, text: String, tip: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.tooltip_text = tip
	cb.button_pressed = true
	grid.add_child(cb)
	return cb

func open(p_view: IDPRoomView, styles: Array[IDPFreeformStyle], sets: Array[IDPStampSet]) -> void:
	view = p_view
	_styles = styles
	_sets = sets
	_previewing = false
	_set.clear()
	for s in sets:
		_set.add_item(s.get_display_name())
	if sets.is_empty():
		_set.add_item("No stamp sets (structures and leaves only)")
	_set.select(0)
	_fill_categories()
	_fill_styles(_struct_style, "back", ["ruin", "back"])
	_fill_styles(_front_style, "front", ["foreground", "silhouette", "leaf"])
	_seed.value = absi(hash(view.room_id)) % 10000
	popup_centered()

func _stamp_set() -> IDPStampSet:
	return _sets[_set.selected] if _set.selected >= 0 and _set.selected < _sets.size() else null

func _fill_categories() -> void:
	_hang_cat.clear()
	_leaf_cat.clear()
	for c in _plant_box.get_children():
		c.queue_free()
	_leaf_cat.add_item("(none)")
	var st := _stamp_set()
	if not st:
		_hang_cat.add_item("(none)")
		return
	var by := IDPFreeformDecorator.categories_by_anchor(st)
	for cat in st.get_categories():
		_hang_cat.add_item(cat)
		_leaf_cat.add_item(cat)
		if cat in by.hang and _hang_cat.selected <= 0:
			_hang_cat.select(_hang_cat.item_count - 1)
		var lower := cat.to_lower()
		if lower.contains("leaf") or lower.contains("bg"):
			_leaf_cat.select(_leaf_cat.item_count - 1)
		if cat in by.stand:
			var cb := CheckBox.new()
			cb.text = cat
			cb.button_pressed = not (lower.contains("leaf") or lower.contains("silhouette") or lower.contains("bg"))
			_plant_box.add_child(cb)

## Lists the styles, picking one whose default layer is [param layer] and whose name has one
## of [param words] (or just the layer).
func _fill_styles(o: OptionButton, layer: String, words: Array) -> void:
	o.clear()
	var pick := -1
	var fallback := -1
	for i in _styles.size():
		var st := _styles[i]
		o.add_item(st.get_list_name(), i)
		if st.default_layer == layer:
			if fallback < 0:
				fallback = i
			for w in words:
				if pick < 0 and st.get_display_name().to_lower().contains(w):
					pick = i
	o.select(pick if pick >= 0 else maxi(fallback, 0))

func _run() -> Dictionary:
	var painter := view.painter
	painter.checkpoint()
	var d := IDPFreeformDecorator.new()
	d.stamp_set = _stamp_set()
	d.hanging = _hang.button_pressed and d.stamp_set != null
	d.hanging_category = _hang_cat.get_item_text(_hang_cat.selected) if d.hanging and _hang_cat.selected >= 0 else ""
	d.floor_plants = _plants.button_pressed
	var cats: PackedStringArray = []
	for cb in _plant_box.get_children():
		if cb is CheckBox and cb.button_pressed and not cb.is_queued_for_deletion():
			cats.append(cb.text)
	d.floor_categories = cats
	d.structures = _structs.button_pressed
	var kinds: Array[int] = []
	for cb in _kind_box.get_children():
		if cb.button_pressed:
			kinds.append(int(cb.get_meta(&"kind")))
	d.structure_kinds = kinds
	d.structure_style = _styles[_struct_style.get_selected_id()] if _struct_style.selected >= 0 and not _styles.is_empty() else null
	d.leaf_category = _leaf_cat.get_item_text(_leaf_cat.selected) if _leaf_cat.selected > 0 else ""
	d.foreground = _front.button_pressed
	d.foreground_style = _styles[_front_style.get_selected_id()] if _front_style.selected >= 0 and not _styles.is_empty() else null
	d.density = _density.value / 100.0
	d.seed_value = int(_seed.value)
	d.use_world_room(view.world, view.room_id)
	return d.decorate(painter)

func _report(r: Dictionary, preview: bool) -> void:
	view._changed("%s %d hanging, %d plant(s), %d structure(s), %d foreground shape(s)%s. Ctrl+Z undoes it." % [
		"Preview:" if preview else "Decorated:", r.hanging, r.plants, r.structures, r.foreground,
		" (replacing %d placed before)" % r.removed if r.removed > 0 else ""])

func preview() -> void:
	if _previewing:
		view.painter.undo()
	_report(_run(), true)
	_previewing = true

func _on_confirmed() -> void:
	if not _previewing:
		_report(_run(), false)
	_previewing = false

func _take_back() -> void:
	if _previewing and view and view.painter:
		view.painter.undo()
		view._changed("Decoration cancelled.")
	_previewing = false
