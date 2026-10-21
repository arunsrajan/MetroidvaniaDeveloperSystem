@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_options_menu.svg")
class_name MDSOptionsMenu
extends VBoxContainer
## The options (the pause menu's Options tab, and the title screen's): a volume per audio bus, the
## window, accessibility (game speed 50 to 100%, assist mode, screen shake and flash intensity,
## camera motion, text size, input glyphs, toggled glide) and the controls, each action rebindable
## for keyboard and gamepad. Every change applies at once and is kept in
## [code]user://mds_options.cfg[/code] ([MDSOptions]). Sliders move with left and right; the
## other rows change with accept.

signal changed(option: String)

## Actions listed for rebinding (empty: the kit's).
@export var actions: PackedStringArray = []

## Option name -> its control ("shake", "assist", "bind:jump:key"...).
var controls: Dictionary = {}
var _list: VBoxContainer
## The action waiting for a new binding, and whether a gamepad one ("" when none).
var listening_action := ""
var listening_pad := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = MDSGameplayUi.scroll_list(self)
	MDSOptions.ensure_loaded(get_tree())
	refresh()

## Builds the rows again from the options.
func refresh() -> void:
	MDSGameplayUi.clear(_list)
	controls.clear()
	_heading("Audio")
	for i in AudioServer.bus_count:
		var bus := AudioServer.get_bus_name(i)
		_slider("volume:" + bus, "%s volume" % bus, 0, 100, 5, MDSOptions.volume(bus) * 100.0, func(v: float) -> void: MDSOptions.volumes[bus] = v / 100.0)
	_heading("Display")
	_toggle("fullscreen", "Fullscreen", MDSOptions.fullscreen, func(on: bool) -> void: MDSOptions.fullscreen = on)
	_toggle("vsync", "VSync", MDSOptions.vsync, func(on: bool) -> void: MDSOptions.vsync = on)
	_heading("Accessibility")
	_slider("game_speed", "Game speed %", 50, 100, 5, MDSOptions.game_speed * 100.0, func(v: float) -> void: MDSOptions.game_speed = v / 100.0)
	_cycle("assist", "Assist mode", MDSOptions.ASSIST_NAMES, MDSOptions.assist, func(i: int) -> void: MDSOptions.assist = i)
	_slider("shake", "Screen shake %", 0, 100, 10, MDSOptions.shake * 100.0, func(v: float) -> void: MDSOptions.shake = v / 100.0)
	_slider("flash", "Flash intensity %", 0, 100, 10, MDSOptions.flash * 100.0, func(v: float) -> void: MDSOptions.flash = v / 100.0)
	_cycle("camera_motion", "Camera motion", MDSRoomCamera.MOTION_NAMES, MDSOptions.camera_motion, func(i: int) -> void: MDSOptions.camera_motion = i)
	var sizes := PackedStringArray()
	for s in MDSOptions.TEXT_SCALES:
		sizes.append("%d%%" % int(round(s * 100.0)))
	_cycle("text_size", "Text size", sizes, MDSOptions.text_size, func(i: int) -> void: MDSOptions.text_size = i)
	_cycle("text_speed", "Text speed", MDSOptions.TEXT_SPEED_NAMES, MDSOptions.text_speed, func(i: int) -> void: MDSOptions.text_speed = i)
	_cycle("glyphs", "Button prompts", MDSOptions.GLYPH_NAMES, int(MDSOptions.glyphs), func(i: int) -> void: MDSOptions.glyphs = i as MDSOptions.Glyphs)
	_toggle("toggle_glide", "Glide: press to toggle", MDSOptions.toggle_glide, func(on: bool) -> void: MDSOptions.toggle_glide = on)
	_heading("Controls")
	var list := actions if not actions.is_empty() else PackedStringArray(MDSGameplaySetup.ACTIONS.keys())
	for a in list:
		if not InputMap.has_action(a):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		_list.add_child(row)
		var l := MDSGameplayUi.label(row, a.capitalize(), 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for pad in [false, true]:
			var b := MDSGameplayUi.button(row, _binding_text(a, pad))
			b.custom_minimum_size = Vector2(130, 0)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.pressed.connect(listen.bind(a, pad))
			controls["bind:%s:%s" % [a, "pad" if pad else "key"]] = b
	MDSGameplayUi.button(_list, "Reset controls", func() -> void:
		MDSOptions.unbind()
		_commit("bindings")
		refresh())

## The control of option [param option], or null.
func get_control(option: String) -> Control:
	return controls.get(option)

func _heading(text: String) -> void:
	MDSGameplayUi.label(_list, text, 17, MDSGameplayUi.GOLD)

func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_list.add_child(row)
	var l := MDSGameplayUi.label(row, text, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

func _slider(option: String, text: String, lo: float, hi: float, step: float, value: float, set_value: Callable) -> HSlider:
	var row := _row(text)
	var v := MDSGameplayUi.label(row, str(int(value)), 16, MDSGameplayUi.DIM)
	v.custom_minimum_size = Vector2(44, 0)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = clampf(value, lo, hi)
	s.custom_minimum_size = Vector2(220, 24)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(x: float) -> void:
		v.text = str(int(x))
		set_value.call(x)
		_commit(option))
	row.add_child(s)
	controls[option] = s
	return s

func _toggle(option: String, text: String, on: bool, set_value: Callable) -> CheckButton:
	var row := _row(text)
	var c := CheckButton.new()
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(x: bool) -> void:
		set_value.call(x)
		_commit(option))
	row.add_child(c)
	controls[option] = c
	return c

## A button that steps through [param names] on accept.
func _cycle(option: String, text: String, names: PackedStringArray, index: int, set_value: Callable) -> Button:
	var row := _row(text)
	var b := MDSGameplayUi.button(row, "")
	b.custom_minimum_size = Vector2(220, 0)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.set_meta(&"mds_index", clampi(index, 0, names.size() - 1))
	b.text = "◂ %s ▸" % names[b.get_meta(&"mds_index")]
	b.pressed.connect(func() -> void:
		var i := (int(b.get_meta(&"mds_index")) + 1) % names.size()
		b.set_meta(&"mds_index", i)
		b.text = "◂ %s ▸" % names[i]
		set_value.call(i)
		_commit(option))
	controls[option] = b
	return b

func _commit(option: String) -> void:
	MDSOptions.apply(get_tree() if is_inside_tree() else null)
	MDSOptions.save_options()
	changed.emit(option)

func _binding_text(action: String, pad: bool) -> String:
	var e := MDSOptions.get_binding(action, pad)
	return MDSOptions.event_name(e) if e else "—"

## Waits for the next key (or with [param pad], gamepad button or stick) to bind to [param action].
## Escape cancels.
func listen(action: String, pad: bool) -> void:
	listening_action = action
	listening_pad = pad
	var b: Button = controls.get("bind:%s:%s" % [action, "pad" if pad else "key"])
	if b:
		b.text = "Press…"

func _input(event: InputEvent) -> void:
	if listening_action.is_empty() or not event.is_pressed() or event.is_echo():
		return
	var action := listening_action
	var b: Button = controls.get("bind:%s:%s" % [action, "pad" if listening_pad else "key"])
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		listening_action = ""
		if b:
			b.text = _binding_text(action, listening_pad)
		get_viewport().set_input_as_handled()
		return
	var fits := (event is InputEventKey) if not listening_pad else (event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6))
	if not fits:
		return
	get_viewport().set_input_as_handled()
	var e := event.duplicate() as InputEvent
	e.device = -1
	if e is InputEventJoypadMotion:
		(e as InputEventJoypadMotion).axis_value = signf((e as InputEventJoypadMotion).axis_value)
	MDSOptions.bind(action, e)
	listening_action = ""
	_commit("bind:" + action)
	if b:
		b.text = _binding_text(action, listening_pad)
		b.grab_focus.call_deferred()
