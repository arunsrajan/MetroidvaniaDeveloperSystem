@tool
class_name MDSTraceDialog
extends ConfirmationDialog
## The Room view's "Trace drawing..." dialog (see [MDSDrawingTracer]): pick a drawing (any
## image on disk, or drop one on the Room view), say how it is drawn (freeform styles, solid
## colors, tiles, or the drawing itself with collision) and what each of its colors becomes (a
## layer, and a style, color or tile fill), and trace it into the room. Preview traces it so it
## can be looked at (Cancel takes it back out).

signal traced(report: Dictionary)

const IMAGE_FILTERS: PackedStringArray = ["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.svg ; Images"]
const OUTPUT_TIPS: PackedStringArray = [
	"Each color becomes freeform shapes in the freeform style picked for it: textured rock, moss, ledges...",
	"Each color becomes freeform shapes filled with a solid color: the drawing's own color, or one picked for it",
	"Each color paints the room's tile grid: with a terrain (autotiled), tiles of a kind, the tiles picked in the tile palette (a spritesheet), or solid tiles of its own color",
	"The drawing goes into the room as it is drawn: a picture behind the terrain, one at its depth and one in front, each with its layer's colors, the paper cut out. Collision gives its terrain and platforms invisible freeform shapes (one-way for platforms), like CollisionPolygon2D",
]

var view: MDSRoomView
var tracer := MDSDrawingTracer.new()
var _styles: Array[MDSFreeformStyle] = []
var _path: LineEdit
var _output: OptionButton
var _original: TextureRect
var _layers: TextureRect
var _rows: GridContainer
var _what: Label
var _fit: OptionButton
var _crop: CheckBox
var _detail: HSlider
var _min_size: SpinBox
var _bleed: SpinBox
var _round: CheckBox
var _replace: CheckBox
var _picture_row: Control
var _collision: CheckBox
var _cut_paper: CheckBox
var _info: Label
var _file_dialog: EditorFileDialog
var _previewing := false
var _last: Dictionary = {}

func _init() -> void:
	title = "Trace drawing"
	ok_button_text = "Trace into room"
	var box := VBoxContainer.new()
	MDSUi.scroll_content(self, box)
	box.add_child(MDSUi.hint("Draws the room from a picture. Black, grey and brown: solid terrain; red, orange and yellow: one-way platforms; green: background; blue and purple: foreground; white or transparent: nothing (paper). The drawing covers the room's box on the map. Draw it with freeform styles, solid colors, tiles from a spritesheet or terrain, or keep the drawing itself and give its terrain collision."))
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
	var output_row := HBoxContainer.new()
	box.add_child(output_row)
	output_row.add_child(MDSUi.label("Draw with"))
	_output = OptionButton.new()
	for i in MDSDrawingTracer.OUTPUT_NAMES.size():
		_output.add_item(MDSDrawingTracer.OUTPUT_NAMES[i], i)
		_output.set_item_tooltip(i, OUTPUT_TIPS[i])
	_output.tooltip_text = "How the drawing goes into the room"
	_output.item_selected.connect(func(idx: int) -> void: set_output(_output.get_item_id(idx)))
	output_row.add_child(_output)
	var pictures := HBoxContainer.new()
	pictures.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(pictures)
	_original = _picture("The drawing")
	pictures.add_child(_original)
	_layers = _picture("What it becomes: terrain grey-blue, platforms orange, background green, foreground purple")
	pictures.add_child(_layers)
	box.add_child(MDSUi.title("Colors", 13))
	_what = MDSUi.hint("")
	box.add_child(_what)
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
	_replace.tooltip_text = "Remove what an earlier trace of this room made first (its shapes, pictures and tiles), so you can redraw and trace again"
	var checks := HBoxContainer.new()
	checks.add_child(_crop)
	checks.add_child(_round)
	checks.add_child(_replace)
	box.add_child(checks)
	_collision = CheckBox.new()
	_collision.text = "Collision for its terrain"
	_collision.button_pressed = true
	_collision.tooltip_text = "Give the drawing's terrain colors invisible freeform shapes to collide with, following the drawing's outlines (like CollisionPolygon2D), and its platform colors one-way ones. Edit them with Freeform > Edit; the editor outlines them"
	_cut_paper = CheckBox.new()
	_cut_paper.text = "Cut out the paper"
	_cut_paper.button_pressed = true
	_cut_paper.tooltip_text = "Make the paper (colors set to Nothing) transparent, so the room's background shows through it"
	_picture_row = HBoxContainer.new()
	_picture_row.add_child(_collision)
	_picture_row.add_child(_cut_paper)
	box.add_child(_picture_row)
	for check in [_collision, _cut_paper]:
		check.toggled.connect(func(_on: bool) -> void: _show_colors())
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
	if view.world:
		if path.is_empty():
			path = str(view.world.get_room_value(view.room_id, "drawing", ""))
		# The way the room was traced last time.
		var last := int(view.world.get_room_value(view.room_id, "drawing_output", tracer.output))
		tracer.output = clampi(last, 0, MDSDrawingTracer.OUTPUT_NAMES.size() - 1) as MDSDrawingTracer.Output
	_output.select(_output.get_item_index(tracer.output))
	MDSUi.popup_fitted(self, 640)
	if not path.is_empty():
		load_drawing(path)
	else:
		_show_colors()

## Picks how the drawing goes into the room (see [enum MDSDrawingTracer.Output]).
func set_output(output: int) -> void:
	tracer.output = output as MDSDrawingTracer.Output
	_output.select(_output.get_item_index(output))
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

## Gives each color the style, solid color and tile fill its layer suits best.
func _default_styles() -> void:
	for c in tracer.colors:
		c.style = _style_for_layer(c.layer)
		c.fill_color = c.color
		c.fill = _fill_for_layer(c.layer, c.color)

## The tile fill a color of [param layer] paints by default: the Room view's fill for that
## layer (a terrain, a kind, palette tiles), or solid tiles of the color itself where the view
## paints a solid color.
func _fill_for_layer(layer: int, color: Color) -> Dictionary:
	var f: Dictionary = {}
	if view and view.canvas:
		match layer:
			MDSDrawingTracer.Layer.IGNORE:
				return {}
			MDSDrawingTracer.Layer.BACKGROUND:
				f = view.canvas.fills.get(MDSRoomCanvas.Tool.BACKGROUND, {})
			MDSDrawingTracer.Layer.FOREGROUND:
				f = view.canvas.fills.get(MDSRoomCanvas.Tool.FOREGROUND, {})
			_:
				f = view.canvas.fills.get(MDSRoomCanvas.Tool.TERRAIN, {})
	if f.is_empty() or str(f.get("type", "")) == "color":
		return {"type": "color", "color": color}
	return f.duplicate()

## Tile fills a color can paint, as [text, icon, fill]: its own color, then the tileset's
## terrains and kinds, then the tiles picked in the palette.
func _tile_choices(color: Color) -> Array:
	var out: Array = [["Its color (solid tiles)", MDSUi.color_icon(color), {"type": "color", "color": color}]]
	if view and view.painter:
		for c in view._fill_choices():
			if str(c[2].get("type", "")) in ["terrain", "kind"]:
				out.append(c)
		if view.palette and view.palette.has_selection():
			out.append(["Palette tiles (%s)" % view.palette.describe_fill(), null, view.palette.get_fill()])
	return out

static func _same_tile_fill(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("type", "")) != str(b.get("type", "")):
		return false
	match str(a.get("type", "")):
		"terrain":
			return a.get("set") == b.get("set") and a.get("terrain") == b.get("terrain")
		"kind":
			return a.get("kind") == b.get("kind")
		"stamp":
			return a.get("source") == b.get("source") and a.get("region") == b.get("region")
	return true

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
		_rows.remove_child(c)
		c.queue_free()
	_original.texture = ImageTexture.create_from_image(tracer.image) if tracer.image else null
	_refresh_layers()
	_update_options()
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
		var what := _what_picker(c)
		_rows.add_child(what)
		layer.item_selected.connect(func(idx: int) -> void:
			c.layer = layer.get_item_id(idx)
			c.style = _style_for_layer(c.layer)
			c.fill = _fill_for_layer(c.layer, c.color)
			_show_colors())

## What a color is drawn with, for the current way of drawing: its freeform style, its solid
## color, or its tile fill (the drawing itself needs nothing).
func _what_picker(c: Dictionary) -> Control:
	var off: bool = c.layer == MDSDrawingTracer.Layer.IGNORE
	match tracer.output:
		MDSDrawingTracer.Output.COLORS:
			var pick := ColorPickerButton.new()
			pick.color = c.get("fill_color", c.color)
			pick.custom_minimum_size = Vector2(220, 0) * MDSUi.editor_scale()
			pick.tooltip_text = "Color the shapes of this color are filled with"
			pick.disabled = off
			pick.color_changed.connect(func(col: Color) -> void: c.fill_color = col)
			return pick
		MDSDrawingTracer.Output.TILES:
			var fill := OptionButton.new()
			fill.fit_to_longest_item = false
			fill.clip_text = true
			fill.custom_minimum_size.x = 220 * MDSUi.editor_scale()
			fill.tooltip_text = "Tiles this color paints: solid tiles of its color, a terrain (autotiled), random tiles of a kind, or the tiles picked in the tile palette (pick them there first)"
			var current: Dictionary = c.get("fill", {})
			var matched := false
			for choice in _tile_choices(c.color):
				if choice[1]:
					fill.add_icon_item(choice[1], choice[0])
				else:
					fill.add_item(choice[0])
				fill.set_item_metadata(fill.item_count - 1, choice[2])
				if not matched and _same_tile_fill(choice[2], current):
					fill.select(fill.item_count - 1)
					matched = true
			if not matched and not current.is_empty():
				# Tiles picked in the palette before it changed: still listed, still picked.
				fill.add_item("Palette tiles picked before")
				fill.set_item_metadata(fill.item_count - 1, current)
				fill.select(fill.item_count - 1)
			fill.disabled = off
			fill.item_selected.connect(func(idx: int) -> void: c.fill = (fill.get_item_metadata(idx) as Dictionary).duplicate())
			return fill
		MDSDrawingTracer.Output.PICTURE:
			var depth := {MDSDrawingTracer.Layer.IGNORE: "cut out (paper)" if _cut_paper.button_pressed else "kept, at the terrain's depth", MDSDrawingTracer.Layer.TERRAIN: "as drawn, with collision" if _collision.button_pressed else "as drawn",
				MDSDrawingTracer.Layer.PLATFORM: "as drawn, one-way collision" if _collision.button_pressed else "as drawn", MDSDrawingTracer.Layer.BACKGROUND: "as drawn, behind", MDSDrawingTracer.Layer.FOREGROUND: "as drawn, in front"}
			return MDSUi.label(depth[c.layer])
	var style := OptionButton.new()
	style.fit_to_longest_item = false
	style.custom_minimum_size.x = 220 * MDSUi.editor_scale()
	style.tooltip_text = "Freeform style of the shapes of this color"
	_fill_styles(style, c.get("style"))
	style.disabled = off
	style.item_selected.connect(func(idx: int) -> void: c.style = style.get_item_metadata(idx))
	return style

## Shows the options the current way of drawing uses.
func _update_options() -> void:
	var o := tracer.output
	var shapes := o != MDSDrawingTracer.Output.TILES
	_picture_row.visible = o == MDSDrawingTracer.Output.PICTURE
	_detail.editable = shapes
	_round.disabled = not shapes
	_what.text = ["Each color's layer and freeform style:", "Each color's layer and the solid color it is filled with:",
		"Each color's layer and the tiles it paints (terrain and platforms on the Terrain layer, background and foreground on theirs):",
		"Each color's layer: the drawing is kept as it is drawn, split by depth."][o]

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
	tracer.collision = _collision.button_pressed
	tracer.cut_paper = _cut_paper.button_pressed
	painter.checkpoint()
	var r := tracer.apply(painter, _replace.button_pressed)
	if not str(r.get("error", "")).is_empty():
		painter.undo()
		return r
	r.error = ""
	if MDSDrawingTracer.made(r) == 0:
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
		view.world.set_room_value(view.room_id, "drawing_output", int(tracer.output))
	view.report_trace(r, false)
	traced.emit(r)

func _take_back() -> void:
	if _previewing and view and view.painter:
		view.painter.undo()
		view.report_trace({"error": "Trace cancelled."}, false)
	_previewing = false
