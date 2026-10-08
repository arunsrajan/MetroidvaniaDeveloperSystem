@tool
class_name MDSTraceDialog
extends ConfirmationDialog
## The Room view's "Trace drawing..." dialog (see [MDSDrawingTracer]): pick a drawing (any
## image on disk, or drop one on the Room view), say what each of its colors becomes (a layer
## and a freeform style), and trace it into the room. Preview traces it so it can be looked at
## (Cancel takes it back out).

signal traced(report: Dictionary)

const IMAGE_FILTERS: PackedStringArray = ["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.svg ; Images"]

var view: MDSRoomView
var tracer := MDSDrawingTracer.new()
var _styles: Array[MDSFreeformStyle] = []
var _path: LineEdit
var _original: TextureRect
var _layers: TextureRect
var _rows: GridContainer
var _fit: OptionButton
var _crop: CheckBox
var _detail: HSlider
var _min_size: SpinBox
var _bleed: SpinBox
var _round: CheckBox
var _replace: CheckBox
var _info: Label
var _file_dialog: EditorFileDialog
var _previewing := false
var _last: Dictionary = {}

func _init() -> void:
	title = "Trace drawing"
	ok_button_text = "Trace into room"
	var box := VBoxContainer.new()
	MDSUi.scroll_content(self, box)
	box.add_child(MDSUi.hint("Draws the room from a picture: each color of the drawing becomes freeform shapes of the style you pick. Black, grey and brown: solid terrain; red, orange and yellow: one-way platforms; green: background; blue and purple: foreground; white or transparent: nothing. The drawing covers the room's box on the map."))
	var file_row := HBoxContainer.new()
	box.add_child(file_row)
	file_row.add_child(MDSUi.label("Drawing"))
	_path = LineEdit.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.placeholder_text = "an image file (drag one from the FileSystem dock)"
	MDSUi.path_drop(_path)
	MDSUi.commit_line(_path, func(t: String) -> void: load_drawing(t.strip_edges()))
	file_row.add_child(_path)
	var choose := MDSUi.button("Choose...", "Pick an image anywhere on this computer")
	choose.pressed.connect(_choose_file)
	file_row.add_child(choose)
	var pictures := HBoxContainer.new()
	pictures.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(pictures)
	_original = _picture("The drawing")
	pictures.add_child(_original)
	_layers = _picture("What it becomes: terrain grey-blue, platforms orange, background green, foreground purple")
	pictures.add_child(_layers)
	box.add_child(MDSUi.title("Colors", 13))
	_rows = GridContainer.new()
	_rows.columns = 4
	box.add_child(_rows)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(MDSUi.label("Fit"))
	_fit = OptionButton.new()
	_fit.add_item("Stretch over the room's box")
	_fit.add_item("Keep its proportions")
	_fit.tooltip_text = "How the drawing is laid over the room's box on the map"
	grid.add_child(_fit)
	grid.add_child(MDSUi.label("Detail"))
	_detail = HSlider.new()
	_detail.min_value = 0
	_detail.max_value = 100
	_detail.value = 50
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.tooltip_text = "Left: smooth outlines with few points. Right: follows every wiggle of the drawing"
	grid.add_child(_detail)
	_min_size = _spin(grid, "Smallest shape", 0, 1000, 24, "px", "Shapes smaller than this across are dropped as specks")
	_bleed = _spin(grid, "Run on past edges", 0, 1000, 64, "px", "Shapes touching the drawing's edge run on this far past the room's edge, out of the camera's sight")
	_crop = CheckBox.new()
	_crop.text = "Fit what is drawn"
	_crop.button_pressed = true
	_crop.tooltip_text = "Cut off the paper around the drawing, so what is drawn fills the room's width and height (off: the whole picture covers the room)"
	_round = CheckBox.new()
	_round.text = "Round outlines"
	_round.button_pressed = true
	_round.tooltip_text = "Round the outlines through their points (off: straight edges, for a blockout)"
	_replace = CheckBox.new()
	_replace.text = "Replace the last trace"
	_replace.button_pressed = true
	_replace.tooltip_text = "Remove the shapes an earlier trace of this room made first, so you can redraw and trace again"
	var checks := HBoxContainer.new()
	checks.add_child(_crop)
	checks.add_child(_round)
	checks.add_child(_replace)
	box.add_child(checks)
	_info = MDSUi.hint("")
	box.add_child(_info)
	add_button("Preview", false, "preview")
	custom_action.connect(func(action: StringName) -> void:
		if action == &"preview":
			preview())
	confirmed.connect(_on_confirmed)
	canceled.connect(_take_back)
	close_requested.connect(_take_back)

func _picture(tip: String) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(260, 150) * MDSUi.editor_scale()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.tooltip_text = tip
	return t

func _spin(grid: GridContainer, text: String, lo: float, hi: float, value: float, suffix: String, tip: String) -> SpinBox:
	grid.add_child(MDSUi.label(text))
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.suffix = suffix
	s.tooltip_text = tip
	grid.add_child(s)
	return s

## Opens the dialog for the view's room, with [param path] (else the room's last drawing).
func open(p_view: MDSRoomView, styles: Array[MDSFreeformStyle], path := "") -> void:
	view = p_view
	_styles = styles
	_previewing = false
	if path.is_empty() and view.world:
		path = str(view.world.get_room_value(view.room_id, "drawing", ""))
	MDSUi.popup_fitted(self, 640)
	if not path.is_empty():
		load_drawing(path)
	else:
		_show_colors()

func load_drawing(path: String) -> void:
	if path.is_empty():
		return
	_path.text = path
	var err := tracer.load_image(path)
	if err != OK:
		_info.text = "Could not read %s (error %d). PNG, JPG, WebP, BMP, TGA and SVG files work." % [path.get_file(), err]
		tracer.image = null
		tracer.colors.clear()
	else:
		_info.text = "%s: %d x %d px traced, %d color(s)." % [path.get_file(), tracer.image.get_width(), tracer.image.get_height(), tracer.colors.size()]
	_default_styles()
	_show_colors()

func _choose_file() -> void:
	if not _file_dialog:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = IMAGE_FILTERS
		_file_dialog.file_selected.connect(load_drawing)
		add_child(_file_dialog)
	_file_dialog.popup_file_dialog()

## Gives each color the style its layer suits best.
func _default_styles() -> void:
	for c in tracer.colors:
		c.style = _style_for_layer(c.layer)

func _style_for_layer(layer: int) -> MDSFreeformStyle:
	var current: MDSFreeformStyle = view.canvas.freeform_style if view and view.canvas else null
	var want := ""
	match layer:
		MDSDrawingTracer.Layer.IGNORE:
			return null
		MDSDrawingTracer.Layer.BACKGROUND:
			want = "back"
		MDSDrawingTracer.Layer.FOREGROUND:
			want = "front"
		MDSDrawingTracer.Layer.PLATFORM:
			for st in _styles:
				if st.get_role() == MDSFreeformStyle.Role.PLATFORM:
					return st
	if want.is_empty():
		if current and current.default_layer == "terrain" and current.solid:
			return current
		want = "terrain"
	for st in _styles.slice(MDSFreeformStyle.BUILTIN_COUNT) + _styles.slice(0, MDSFreeformStyle.BUILTIN_COUNT):
		if st.default_layer == want and (want != "terrain" or st.get_role() == MDSFreeformStyle.Role.TERRAIN):
			return st
	return _styles[0] if not _styles.is_empty() else null

func _show_colors() -> void:
	for c in _rows.get_children():
		c.queue_free()
	_original.texture = ImageTexture.create_from_image(tracer.image) if tracer.image else null
	_refresh_layers()
	if tracer.colors.is_empty():
		_rows.add_child(MDSUi.hint("Pick a drawing first."))
		return
	for i in tracer.colors.size():
		var c: Dictionary = tracer.colors[i]
		var swatch := ColorRect.new()
		swatch.color = c.color
		swatch.custom_minimum_size = Vector2(28, 20) * MDSUi.editor_scale()
		_rows.add_child(swatch)
		_rows.add_child(MDSUi.label("%d%%" % roundi(c.share * 100.0)))
		var layer := OptionButton.new()
		for l in MDSDrawingTracer.LAYER_NAMES.size():
			layer.add_item(MDSDrawingTracer.LAYER_NAMES[l], l)
		layer.select(c.layer)
		layer.tooltip_text = "What this color becomes"
		_rows.add_child(layer)
		var style := OptionButton.new()
		style.fit_to_longest_item = false
		style.custom_minimum_size.x = 220 * MDSUi.editor_scale()
		style.tooltip_text = "Freeform style of the shapes of this color"
		_fill_styles(style, c.get("style"))
		style.disabled = c.layer == MDSDrawingTracer.Layer.IGNORE
		_rows.add_child(style)
		layer.item_selected.connect(func(idx: int) -> void:
			c.layer = layer.get_item_id(idx)
			c.style = _style_for_layer(c.layer)
			_fill_styles(style, c.style)
			style.disabled = c.layer == MDSDrawingTracer.Layer.IGNORE
			_refresh_layers())
		style.item_selected.connect(func(idx: int) -> void: c.style = style.get_item_metadata(idx))

func _fill_styles(o: OptionButton, current: Variant) -> void:
	o.clear()
	for st in _styles:
		o.add_item(st.get_list_name())
		o.set_item_metadata(o.item_count - 1, st)
		if st == current:
			o.select(o.item_count - 1)

func _refresh_layers() -> void:
	var img := tracer.layer_preview()
	_layers.texture = ImageTexture.create_from_image(img) if img else null

func _run() -> Dictionary:
	if not tracer.image or tracer.colors.is_empty():
		return {"error": "Pick a drawing first."}
	var painter := view.painter
	var b := Rect2()
	var first := true
	for r in view.world.get_local_rects(view.room_id):
		b = r if first else b.merge(r)
		first = false
	tracer.target = b if b.has_area() else Rect2(Vector2.ZERO, Vector2(1152, 648))
	tracer.keep_aspect = _fit.selected == 1
	tracer.crop = _crop.button_pressed
	tracer.detail = _detail.value / 100.0
	tracer.min_size = _min_size.value
	tracer.bleed = _bleed.value
	tracer.smooth = _round.button_pressed
	painter.checkpoint()
	var r := tracer.apply(painter, _replace.button_pressed)
	r.error = ""
	if r.terrain + r.platform + r.background + r.foreground == 0:
		painter.undo()
		r.error = "Nothing to trace: every color is set to Nothing, or its shapes are smaller than the smallest shape."
	return r

func preview() -> void:
	if _previewing:
		view.painter.undo()
	var r := _run()
	_previewing = r.error.is_empty()
	_last = r
	view.report_trace(r, true)

func _on_confirmed() -> void:
	var r: Dictionary = _last if _previewing else _run()
	_previewing = false
	if r.error.is_empty() and view.world:
		view.world.set_room_value(view.room_id, "drawing", _path.text.strip_edges())
	view.report_trace(r, false)
	traced.emit(r)

func _take_back() -> void:
	if _previewing and view and view.painter:
		view.painter.undo()
		view.report_trace({"error": "Trace cancelled."}, false)
	_previewing = false
