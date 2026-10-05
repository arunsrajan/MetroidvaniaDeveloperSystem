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

## Lets a path field take a file dragged from the FileSystem dock (committing it).
static func path_drop(edit: LineEdit) -> void:
	edit.set_drag_forwarding(Callable(), func(_at: Vector2, d: Variant) -> bool:
		return d is Dictionary and d.get("type", "") == "files" and not Array(d.get("files", [])).is_empty(),
		func(_at: Vector2, d: Variant) -> void:
			edit.text = str(d.files[0])
			edit.text_submitted.emit(edit.text))

## Fields describing the player for the room checks ([code]settings.player[/code], see
## [constant IDPRoomCheck.PLAYER_DEFAULTS]). [param apply] gets the whole new dictionary on
## every change. Max jump height and jump velocity are two views of one value.
static func player_fields(grid: GridContainer, current: Dictionary, apply: Callable) -> void:
	var d := IDPRoomCheck.PLAYER_DEFAULTS.duplicate()
	d.merge(current, true)
	var state := [d]
	var size_edit := field_line(grid, "Player size", "%dx%d" % [int(d.size[0]), int(d.size[1])], "32x64")
	size_edit.tooltip_text = "Width x height of the player's collision box (px), for the room checks' climb test and openings"
	commit_line(size_edit, func(t: String) -> void:
		var parts := t.split("x")
		if parts.size() == 2 and parts[0].to_float() > 0 and parts[1].to_float() > 0:
			state[0].size = [parts[0].to_float(), parts[1].to_float()]
			apply.call(state[0].duplicate()))
	var vel_edit := field_line(grid, "Jump velocity (px/s)", str(d.jump_velocity), "700")
	var grav_edit := field_line(grid, "Gravity (px/s²)", str(d.gravity), "900")
	var height_edit := field_line(grid, "Max jump height (px)", str(int(IDPRoomCheck.max_jump_height(d.jump_velocity, d.gravity))), "")
	height_edit.tooltip_text = "How high a jump rises: v² / 2g. Editing it sets the jump velocity"
	var refresh_height := func() -> void:
		height_edit.text = str(int(IDPRoomCheck.max_jump_height(float(state[0].jump_velocity), float(state[0].gravity))))
	commit_line(vel_edit, func(t: String) -> void:
		state[0].jump_velocity = absf(t.to_float())
		refresh_height.call()
		apply.call(state[0].duplicate()))
	commit_line(grav_edit, func(t: String) -> void:
		state[0].gravity = maxf(1.0, t.to_float())
		refresh_height.call()
		apply.call(state[0].duplicate()))
	commit_line(height_edit, func(t: String) -> void:
		state[0].jump_velocity = snappedf(sqrt(2.0 * float(state[0].gravity) * maxf(1.0, t.to_float())), 0.1)
		vel_edit.text = str(state[0].jump_velocity)
		apply.call(state[0].duplicate()))
	var run_edit := field_line(grid, "Run speed (px/s)", str(d.run_speed), "300")
	commit_line(run_edit, func(t: String) -> void:
		state[0].run_speed = maxf(1.0, t.to_float())
		apply.call(state[0].duplicate()))
	var head_edit := field_line(grid, "Head clearance (px)", str(d.head_clearance), "90")
	head_edit.tooltip_text = "Room the player needs above a platform to stand and jump"
	commit_line(head_edit, func(t: String) -> void:
		state[0].head_clearance = maxf(0.0, t.to_float())
		apply.call(state[0].duplicate()))

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
