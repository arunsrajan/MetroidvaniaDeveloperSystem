@tool
class_name MDSUi
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

# --- Fitting on the screen -----------------------------------------------------------------------

## [param rect] made to fit inside [param usable]: no bigger than it, then moved inside it. An
## empty [param usable] (no screen, as when headless) leaves it as it is.
static func fit_rect(rect: Rect2i, usable: Rect2i) -> Rect2i:
	if not usable.has_area():
		return rect
	var s := rect.size.min(usable.size)
	return Rect2i(rect.position.clamp(usable.position, usable.end - s), s)

## The usable area (without taskbars and docks of the desktop) of the screen [param window] is
## on, in screen px. Empty when there is no screen.
static func usable_screen_rect(window: Window) -> Rect2i:
	var screen := window.current_screen if window else DisplayServer.SCREEN_OF_MAIN_WINDOW
	return DisplayServer.screen_get_usable_rect(screen)

## The usable area of the screen holding most of [param rect] (screen px), else of the main
## window's screen.
static func usable_screen_rect_at(rect: Rect2i) -> Rect2i:
	var best := Rect2i()
	var best_area := 0
	for i in DisplayServer.get_screen_count():
		var u := DisplayServer.screen_get_usable_rect(i)
		var a := u.intersection(rect).get_area()
		if a > best_area:
			best_area = a
			best = u
	return best if best_area > 0 else DisplayServer.screen_get_usable_rect(DisplayServer.SCREEN_OF_MAIN_WINDOW)

## How big a dialog over [param window] may be: 92% of that window when dialogs are drawn
## inside it, else of its screen.
static func popup_limit(window: Window) -> Vector2i:
	var lim := Vector2i(1 << 20, 1 << 20)
	if not window:
		return lim
	if window.gui_embed_subwindows or window.is_embedded():
		lim = Vector2i(Vector2(window.size) * 0.92)
	var usable := usable_screen_rect(window)
	if usable.has_area():
		lim = lim.min(Vector2i(Vector2(usable.size) * 0.92))
	return lim

## Puts [param content] in a scroll area filling [param dialog], so the dialog can be smaller
## than what it shows (a small screen, a big editor scale). [method popup_fitted] sizes it.
static func scroll_content(dialog: AcceptDialog, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	dialog.add_child(scroll)
	dialog.set_meta(&"mds_scroll", scroll)
	# Sized by popup_fitted: wrapping its content would shrink it to the buttons.
	dialog.wrap_controls = false
	return scroll

## Pops [param dialog] up centred, [param width] px wide (times the editor scale) and as tall
## as its content, but never bigger than [method popup_limit]: what doesn't fit scrolls (give
## it a scroll area with [method scroll_content]).
static func popup_fitted(dialog: AcceptDialog, width: float) -> void:
	var parent := dialog.get_parent().get_window() if dialog.get_parent() else null
	var lim := popup_limit(parent)
	var w := mini(int(width * editor_scale()), lim.x)
	dialog.min_size = Vector2i(mini(int(200 * editor_scale()), lim.x), mini(int(120 * editor_scale()), lim.y))
	dialog.set_meta(&"mds_width", w)
	dialog.popup_centered(Vector2i(w, mini(int(240 * editor_scale()), lim.y)))
	fit_dialog_height(dialog)
	# Wrapped text only knows its height once the dialog has its width.
	fit_dialog_height.call_deferred(dialog)

## Makes [param dialog] as tall as its scrolled content needs, within [method popup_limit], and
## keeps it centred on the window it opened over.
static func fit_dialog_height(dialog: AcceptDialog) -> void:
	if not is_instance_valid(dialog) or not dialog.visible:
		return
	# get_meta() with a null default still complains when the key is missing.
	var scroll: ScrollContainer = dialog.get_meta(&"mds_scroll") if dialog.has_meta(&"mds_scroll") else null
	var parent := dialog.get_parent().get_window() if dialog.get_parent() else null
	var lim := popup_limit(parent)
	var want := Vector2i(int(dialog.get_meta(&"mds_width", dialog.size.x)), dialog.size.y)
	if scroll and scroll.get_child_count() > 0:
		var content := scroll.get_child(0) as Control
		var chrome := dialog.size.y - int(scroll.size.y)
		want.y = int(content.get_combined_minimum_size().y) + chrome + 8
	want = want.min(lim).max(dialog.min_size)
	# Centred over the window it opened over, inside that window when drawn in it, else on
	# the screen.
	var pos := dialog.position
	var bounds := Rect2i()
	if parent and dialog.is_embedded():
		bounds = Rect2i(Vector2i.ZERO, parent.size)
		pos = (parent.size - want) / 2
	elif parent:
		bounds = usable_screen_rect(parent)
		pos = parent.position + (parent.size - want) / 2
	var r := fit_rect(Rect2i(pos, want), bounds)
	dialog.position = r.position
	dialog.size = r.size

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

## A weather field ([MDSEnvironment]): typed in ("storm", "rain, fog(ground=1)"), a scene of
## effect nodes dropped on it, or picked from its menu of presets and effects. [param commit]
## gets the new text.
static func weather_field(grid: GridContainer, text: String, value: String, placeholder: String, commit: Callable) -> LineEdit:
	grid.add_child(label(text))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.tooltip_text = "Weather and effects: presets (storm, sandstorm, blizzard...), effects (rain, fog(ground=1), dust_storm(blows_toward=left)...), comma-separated, or a .tscn of effect nodes. none: no weather"
	row.add_child(edit)
	var menu := menu_button("+", "Pick a weather preset, or add an effect")
	var popup := menu.get_popup()
	popup.add_separator("Presets")
	for id in MDSEnvironment.PRESETS:
		popup.add_icon_item(MDSEnvironment.icon(id), MDSEnvironment.display_name(id))
		popup.set_item_metadata(popup.item_count - 1, ["preset", id])
		popup.set_item_tooltip(popup.item_count - 1, MDSEnvironment.describe(id))
	popup.add_separator("Add an effect")
	for id in MDSEnvironment.ambient_ids():
		popup.add_icon_item(MDSEnvironment.icon(id), MDSEnvironment.display_name(id))
		popup.set_item_metadata(popup.item_count - 1, ["effect", id])
		popup.set_item_tooltip(popup.item_count - 1, MDSEnvironment.describe(id))
	popup.add_separator()
	popup.add_item("None (no weather here)")
	popup.set_item_metadata(popup.item_count - 1, ["none", ""])
	popup.add_item("Clear")
	popup.set_item_metadata(popup.item_count - 1, ["clear", ""])
	popup.index_pressed.connect(func(i: int) -> void:
		var m: Variant = popup.get_item_metadata(i)
		if not m is Array:
			return
		var current := edit.text.strip_edges()
		match str(m[0]):
			"preset":
				edit.text = m[1]
			"effect":
				edit.text = m[1] if current.is_empty() or MDSEnvironment.is_none(current) else "%s, %s" % [current, m[1]]
			"none":
				edit.text = "none"
			"clear":
				edit.text = ""
		edit.text_submitted.emit(edit.text))
	row.add_child(menu)
	grid.add_child(row)
	path_drop(edit)
	commit_line(edit, commit)
	return edit

## A parallax background field: a preset picked from its menu, typed in, or a scene of an
## [MDSParallaxBackground] dropped on it. [param commit] gets the new text.
static func parallax_field(grid: GridContainer, text: String, value: String, placeholder: String, commit: Callable) -> LineEdit:
	grid.add_child(label(text))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.tooltip_text = "Parallax background: a preset (dusk_mountains, misty_forest, ruined_city...), or a .tscn holding an MDSParallaxBackground with your layers. none: no background"
	row.add_child(edit)
	var menu := menu_button("+", "Pick a parallax background preset")
	var popup := menu.get_popup()
	for i in range(1, MDSParallaxBackground.PRESET_IDS.size()):
		popup.add_icon_item(MDSEnvironment.icon("parallax"), MDSParallaxBackground.PRESET_NAMES[i])
		popup.set_item_metadata(popup.item_count - 1, MDSParallaxBackground.PRESET_IDS[i])
	popup.add_separator()
	popup.add_item("None (no background here)")
	popup.set_item_metadata(popup.item_count - 1, "none")
	popup.add_item("Clear")
	popup.set_item_metadata(popup.item_count - 1, "")
	popup.index_pressed.connect(func(i: int) -> void:
		edit.text = str(popup.get_item_metadata(i))
		edit.text_submitted.emit(edit.text))
	row.add_child(menu)
	grid.add_child(row)
	path_drop(edit)
	commit_line(edit, commit)
	return edit

## Fields describing the player for the room checks ([code]settings.player[/code], see
## [constant MDSRoomCheck.PLAYER_DEFAULTS]). [param apply] gets the whole new dictionary on
## every change. Max jump height and jump velocity are two views of one value.
static func player_fields(grid: GridContainer, current: Dictionary, apply: Callable) -> void:
	var d := MDSRoomCheck.PLAYER_DEFAULTS.duplicate()
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
	var height_edit := field_line(grid, "Max jump height (px)", str(int(MDSRoomCheck.max_jump_height(d.jump_velocity, d.gravity))), "")
	height_edit.tooltip_text = "How high a jump rises: v² / 2g. Editing it sets the jump velocity"
	var refresh_height := func() -> void:
		height_edit.text = str(int(MDSRoomCheck.max_jump_height(float(state[0].jump_velocity), float(state[0].gravity))))
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
	var tex := color_icon(MDSMapCanvas.TYPE_COLORS.get(type, MDSMapCanvas.TYPE_COLORS[""]))
	_type_icons[type] = tex
	return tex

static func color_icon(color: Color, size := 12) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
