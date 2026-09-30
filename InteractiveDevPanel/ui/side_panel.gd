@tool
class_name IDPSidePanel
extends VBoxContainer
## The left tool panel of Map Dev, like MetSys' editor: every button and picker stacked
## in foldable sections, so the map canvas gets the rest of the screen. The « button
## collapses the panel to a thin strip.

const WIDTH := 220.0

var body: VBoxContainer
var _scroll: ScrollContainer
var _collapse: Button
var _title: Label
var _sections: Dictionary = {} ## title -> [header Button, content Container]

func _init() -> void:
	custom_minimum_size.x = WIDTH * IDPUi.editor_scale()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	add_child(head)
	_title = IDPUi.title("Map Dev", 14)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_collapse = IDPUi.button("«", "Collapse the tool panel (more room for the map)")
	_collapse.flat = true
	_collapse.pressed.connect(func() -> void: set_collapsed(_scroll.visible))
	head.add_child(_collapse)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	_scroll.add_child(body)

func set_collapsed(collapsed: bool) -> void:
	_scroll.visible = not collapsed
	_title.visible = not collapsed
	_collapse.text = "»" if collapsed else "«"
	_collapse.tooltip_text = "Show the tool panel" if collapsed else "Collapse the tool panel (more room for the map)"
	custom_minimum_size.x = 0.0 if collapsed else WIDTH * IDPUi.editor_scale()

func is_collapsed() -> bool:
	return not _scroll.visible

## Adds a foldable section and returns its content box. [param content] replaces the
## default VBoxContainer (e.g. a GridContainer or a box built elsewhere).
func add_section(title: String, content: Control = null) -> Control:
	var header := Button.new()
	header.flat = true
	header.toggle_mode = true
	header.button_pressed = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = "▾ " + title
	body.add_child(header)
	if not content:
		content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	header.toggled.connect(func(on: bool) -> void:
		content.visible = on
		header.text = ("▾ " if on else "▸ ") + title)
	_sections[title] = [header, content]
	return content

## Shows or hides a whole section (header and content).
func set_section_visible(title: String, on: bool) -> void:
	if not _sections.has(title):
		return
	var header: Button = _sections[title][0]
	header.visible = on
	_sections[title][1].visible = on and header.button_pressed

func get_section(title: String) -> Control:
	return _sections[title][1] if _sections.has(title) else null

## A row of controls sharing the width.
static func row(parent: Control, controls: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	for c in controls:
		if c is Control and not c is Label:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(c)
	parent.add_child(h)
	return h

## "Label  [control]" on one line.
static func field(parent: Control, text: String, control: Control) -> HBoxContainer:
	var l := IDPUi.label(text)
	l.custom_minimum_size.x = 52 * IDPUi.editor_scale()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is OptionButton:
		control.fit_to_longest_item = false
		control.clip_text = true
	var h := HBoxContainer.new()
	h.add_child(l)
	h.add_child(control)
	parent.add_child(h)
	return h

## A grid for buttons (tools...), [param columns] wide.
static func grid(parent: Control, columns := 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	return g

## Makes a control fill its grid cell or row.
static func fill(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if c is Button:
		c.clip_text = true
	return c
