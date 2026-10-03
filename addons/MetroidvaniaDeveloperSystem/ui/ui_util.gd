@tool
class_name IDPUi
extends RefCounted
## Small widget helpers shared by the MetSys and non-linear panels.

static var _type_icons: Dictionary = {}

static func label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

static func hint(text: String) -> Label:
	var l := label(text)
	l.modulate.a = 0.6
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	return b

static func menu_button(text: String, tooltip := "") -> MenuButton:
	var m := MenuButton.new()
	m.text = text
	m.flat = false
	m.tooltip_text = tooltip
	return m

## The editor's display scale (1 outside the editor), for sizes set in code.
static func editor_scale() -> float:
	var ei: Object = Engine.get_singleton(&"EditorInterface") if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface") else null
	return ei.get_editor_scale() if ei else 1.0

static func title(text: String, font_size := 15) -> Label:
	var l := label(text)
	l.add_theme_font_size_override("font_size", roundi(font_size * editor_scale()))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func field_line(grid: GridContainer, text: String, value: String, placeholder: String) -> LineEdit:
	grid.add_child(label(text))
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(edit)
	return edit

static func field_option(grid: GridContainer, text: String, values: PackedStringArray, value: String, empty_text: String) -> OptionButton:
	grid.add_child(label(text))
	var opt := OptionButton.new()
	for v in values:
		opt.add_item(v.capitalize() if not v.is_empty() else empty_text)
	opt.select(maxi(0, values.find(value)))
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(opt)
	return opt

## Commits on Enter or focus loss rather than per keystroke, so typing never triggers a
## refresh that would rebuild the field being edited.
static func commit_line(edit: LineEdit, commit: Callable) -> void:
	var last := [edit.text]
	var apply := func() -> void:
		if edit.text != last[0]:
			last[0] = edit.text
			commit.call(edit.text)
	edit.text_submitted.connect(func(_t: String) -> void: apply.call())
	edit.focus_exited.connect(apply)

## Small square icon in the room type's color.
static func type_icon(type: String) -> Texture2D:
	if _type_icons.has(type):
		return _type_icons[type]
	var tex := color_icon(IDPMapCanvas.TYPE_COLORS.get(type, IDPMapCanvas.TYPE_COLORS[""]))
	_type_icons[type] = tex
	return tex

static func color_icon(color: Color, size := 12) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
